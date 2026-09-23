import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/comment.dart";
import "comments_providers.dart";

const int _pageSize = 20;

final class CommentsState {
  const CommentsState({required this.comments, required this.hasMore, this.isLoadingMore = false});

  final List<Comment> comments;
  final bool hasMore;
  final bool isLoadingMore;

  CommentsState copyWith({List<Comment>? comments, bool? hasMore, bool? isLoadingMore}) {
    return CommentsState(
      comments: comments ?? this.comments,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
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
    final List<Comment> more = await ref
        .read(commentsRepositoryProvider)
        .fetchPage(adId: arg, before: current.comments.last.createdAt);
    final CommentsState latest = state.value ?? current;
    state = AsyncData<CommentsState>(
      CommentsState(
        comments: <Comment>[...latest.comments, ...more],
        hasMore: more.length >= _pageSize,
        isLoadingMore: false,
      ),
    );
  }

  Future<void> post(String body) async {
    final Comment comment = await ref.read(commentsRepositoryProvider).create(adId: arg, body: body);
    final CommentsState? current = state.valueOrNull;
    if (current != null) {
      state = AsyncData<CommentsState>(current.copyWith(comments: <Comment>[comment, ...current.comments]));
    }
  }

  Future<void> deleteOwn(String commentId) async {
    await ref.read(commentsRepositoryProvider).deleteOwn(commentId);
    final CommentsState? current = state.valueOrNull;
    if (current != null) {
      state = AsyncData<CommentsState>(
        current.copyWith(
          comments: current.comments.where((Comment c) => c.id != commentId).toList(growable: false),
        ),
      );
    }
  }
}

final AsyncNotifierProviderFamily<CommentsController, CommentsState, String> commentsControllerProvider =
    AsyncNotifierProvider.family<CommentsController, CommentsState, String>(CommentsController.new);
