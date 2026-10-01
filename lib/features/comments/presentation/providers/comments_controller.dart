import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/comment.dart";
import "comments_providers.dart";

const int _pageSize = 20;

/// Reviews posted (+) / deleted (-) this session per Ad, added to the
/// feed's server-side comment_count so the REVIEWS badge updates at once
/// (the feed data isn't refetched after posting). Replies count too, like
/// the server's comment_count.
final StateProviderFamily<int, String> commentCountDeltaProvider =
    StateProvider.family<int, String>((ref, String adId) => 0);

final class CommentsState {
  const CommentsState({
    required this.comments,
    required this.hasMore,
    this.isLoadingMore = false,
    this.replies = const <String, List<Comment>>{},
    this.loadingReplies = const <String>{},
  });

  /// Top-level reviews, newest first.
  final List<Comment> comments;
  final bool hasMore;
  final bool isLoadingMore;

  /// Loaded (= expanded) replies by top-level review id, oldest first.
  final Map<String, List<Comment>> replies;
  final Set<String> loadingReplies;

  CommentsState copyWith({
    List<Comment>? comments,
    bool? hasMore,
    bool? isLoadingMore,
    Map<String, List<Comment>>? replies,
    Set<String>? loadingReplies,
  }) {
    return CommentsState(
      comments: comments ?? this.comments,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      replies: replies ?? this.replies,
      loadingReplies: loadingReplies ?? this.loadingReplies,
    );
  }

  /// [comments] with [parentId]'s reply count changed by [delta].
  List<Comment> _bumpReplyCount(String parentId, int delta) => comments
      .map((Comment c) => c.id == parentId ? c.withReplyCount(c.replyCount + delta) : c)
      .toList(growable: false);
}

/// REVIEWS list + posting for one Ad (CLAUDE.md section 8), keyed by adId.
final class CommentsController extends FamilyAsyncNotifier<CommentsState, String> {
  @override
  Future<CommentsState> build(String adId) async {
    final List<Comment> page = await ref.read(commentsRepositoryProvider).fetchPage(adId: adId);
    return CommentsState(comments: page, hasMore: page.length >= _pageSize);
  }

  Future<void> loadMore() async {
    final CommentsState? current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore || current.comments.isEmpty) {
      return;
    }
    state = AsyncData<CommentsState>(current.copyWith(isLoadingMore: true));
    final List<Comment> more =
        await ref.read(commentsRepositoryProvider).fetchPage(adId: arg, before: current.comments.last.createdAt);
    final CommentsState latest = state.value ?? current;
    state = AsyncData<CommentsState>(
      latest.copyWith(comments: <Comment>[...latest.comments, ...more], hasMore: more.length >= _pageSize, isLoadingMore: false),
    );
  }

  /// Expands [parentId]'s replies (fetches them).
  Future<void> loadReplies(String parentId) async {
    final CommentsState? current = state.valueOrNull;
    if (current == null || current.loadingReplies.contains(parentId)) {
      return;
    }
    state = AsyncData<CommentsState>(current.copyWith(loadingReplies: <String>{...current.loadingReplies, parentId}));
    try {
      final List<Comment> replies = await ref.read(commentsRepositoryProvider).fetchReplies(parentId);
      final CommentsState latest = state.value ?? current;
      state = AsyncData<CommentsState>(
        latest.copyWith(
          replies: <String, List<Comment>>{...latest.replies, parentId: replies},
          loadingReplies: latest.loadingReplies.difference(<String>{parentId}),
        ),
      );
    } catch (_) {
      final CommentsState latest = state.value ?? current;
      state = AsyncData<CommentsState>(
        latest.copyWith(loadingReplies: latest.loadingReplies.difference(<String>{parentId})),
      );
      rethrow;
    }
  }

  void hideReplies(String parentId) {
    final CommentsState? current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData<CommentsState>(
      current.copyWith(replies: Map<String, List<Comment>>.of(current.replies)..remove(parentId)),
    );
  }

  /// Posts a review, or a reply when [parentId] is set (the reply shows
  /// under its review, which is expanded).
  Future<void> post(String body, {String? parentId}) async {
    // Counted BEFORE the request: the live counter (liveAdCountsProvider)
    // can deliver the new server count while the request is still
    // returning, and it resets this adjustment — bumping afterwards would
    // count the review twice.
    final StateController<int> delta = ref.read(commentCountDeltaProvider(arg).notifier);
    delta.state++;
    final Comment comment;
    try {
      comment = await ref.read(commentsRepositoryProvider).create(adId: arg, body: body, parentId: parentId);
    } catch (_) {
      delta.state--;
      rethrow;
    }
    final CommentsState? current = state.valueOrNull;
    if (current != null) {
      if (parentId == null) {
        state = AsyncData<CommentsState>(current.copyWith(comments: <Comment>[comment, ...current.comments]));
      } else {
        state = AsyncData<CommentsState>(
          current.copyWith(
            comments: current._bumpReplyCount(parentId, 1),
            replies: <String, List<Comment>>{
              ...current.replies,
              parentId: <Comment>[...?current.replies[parentId], comment],
            },
          ),
        );
      }
    }
  }

  /// Likes / un-likes [comment] at once on screen, then on the server; the
  /// change is undone if the server refuses.
  Future<void> toggleLike(Comment comment) async {
    final bool liked = !comment.likedByMe;
    _replaceComment(comment.id, (Comment c) => c.withLike(liked: liked));
    try {
      final bool serverLiked = await ref.read(commentsRepositoryProvider).toggleLike(comment.id);
      if (serverLiked != liked) {
        _replaceComment(comment.id, (Comment c) => c.withLike(liked: serverLiked));
      }
    } catch (_) {
      _replaceComment(comment.id, (Comment c) => c.withLike(liked: !liked));
      rethrow;
    }
  }

  /// Applies [change] to the review or reply with [id], wherever it is listed.
  void _replaceComment(String id, Comment Function(Comment) change) {
    final CommentsState? current = state.valueOrNull;
    if (current == null) {
      return;
    }
    Comment apply(Comment c) => c.id == id ? change(c) : c;
    state = AsyncData<CommentsState>(
      current.copyWith(
        comments: current.comments.map(apply).toList(growable: false),
        replies: current.replies.map(
          (String parent, List<Comment> list) => MapEntry<String, List<Comment>>(parent, list.map(apply).toList(growable: false)),
        ),
      ),
    );
  }

  Future<void> deleteOwn(Comment comment) async {
    // Same ordering as post().
    final StateController<int> delta = ref.read(commentCountDeltaProvider(arg).notifier);
    delta.state--;
    try {
      await ref.read(commentsRepositoryProvider).deleteOwn(comment.id);
    } catch (_) {
      delta.state++;
      rethrow;
    }
    final CommentsState? current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final String? parentId = comment.parentId;
    if (parentId == null) {
      state = AsyncData<CommentsState>(
        current.copyWith(
          comments: current.comments.where((Comment c) => c.id != comment.id).toList(growable: false),
          replies: Map<String, List<Comment>>.of(current.replies)..remove(comment.id),
        ),
      );
    } else {
      state = AsyncData<CommentsState>(
        current.copyWith(
          comments: current._bumpReplyCount(parentId, -1),
          replies: <String, List<Comment>>{
            ...current.replies,
            parentId: (current.replies[parentId] ?? const <Comment>[])
                .where((Comment c) => c.id != comment.id)
                .toList(growable: false),
          },
        ),
      );
    }
  }
}

final AsyncNotifierProviderFamily<CommentsController, CommentsState, String> commentsControllerProvider =
    AsyncNotifierProvider.family<CommentsController, CommentsState, String>(CommentsController.new);
