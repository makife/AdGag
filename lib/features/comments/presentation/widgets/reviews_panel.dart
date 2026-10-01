import "dart:async" show Timer, unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../../core/localization/generated/app_localizations.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/supabase/supabase_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/count_label.dart";
import "../../../../shared/widgets/mention_text.dart";
import "../../../../shared/widgets/mini_avatar.dart";
import "../../../moderation/domain/report_target_type.dart";
import "../../../moderation/presentation/widgets/report_sheet.dart";
import "../../../profile/domain/public_profile.dart";
import "../../../profile/presentation/providers/profile_providers.dart";
import "../../domain/comment.dart";
import "../providers/comments_controller.dart";

/// REVIEWS panel (CLAUDE.md section 8). Shown INSIDE the feed card under a
/// shrunken video (not a modal over it — user request: the video should
/// stay visible, smaller, while reading reviews). See AdVideoCard.
///
/// Replies are one level deep: "Reply" on a reply answers its top-level
/// review and starts the text with "@author ". Typing "@" suggests people
/// (the ones you follow first); every @username in a review is tappable.
class ReviewsPanel extends ConsumerStatefulWidget {
  const ReviewsPanel({required this.adId, required this.onClose, this.keyboardInset = 0, super.key});

  final String adId;
  final VoidCallback onClose;

  /// How far the keyboard reaches into this panel from its bottom edge (the
  /// host works it out — the panel doesn't always end at the screen bottom).
  final double keyboardInset;

  @override
  ConsumerState<ReviewsPanel> createState() => _ReviewsPanelState();
}

class _ReviewsPanelState extends ConsumerState<ReviewsPanel> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  bool _posting = false;

  /// The top-level review being replied to (null = a new review).
  Comment? _replyTo;

  /// Username being typed after "@" (null = no suggestion list).
  String? _mentionQuery;
  List<PublicProfile> _suggestions = const <PublicProfile>[];
  Timer? _suggestDebounce;

  static final RegExp _typingMention = RegExp(r"(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_]{0,20})$");

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
        unawaited(ref.read(commentsControllerProvider(widget.adId).notifier).loadMore());
      }
    });
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final TextSelection sel = _input.selection;
    final String beforeCursor =
        sel.isValid && sel.isCollapsed ? _input.text.substring(0, sel.baseOffset) : _input.text;
    final RegExpMatch? m = _typingMention.firstMatch(beforeCursor);
    final String? query = m?.group(1)?.toLowerCase();
    if (query == _mentionQuery) {
      return;
    }
    _mentionQuery = query;
    _suggestDebounce?.cancel();
    if (query == null || query.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const <PublicProfile>[]);
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final List<PublicProfile> found = await ref.read(profileRepositoryProvider).suggestMentions(query);
        if (mounted && _mentionQuery == query) {
          setState(() => _suggestions = found);
        }
      } catch (_) {
        // Suggestions are a convenience; typing the name still works.
      }
    });
  }

  /// Replaces the "@partial" before the cursor with "@username ".
  void _insertMention(String username) {
    final TextSelection sel = _input.selection;
    final int cursor = sel.isValid ? sel.baseOffset : _input.text.length;
    final String before = _input.text.substring(0, cursor);
    final String after = _input.text.substring(cursor);
    final int at = before.lastIndexOf("@");
    if (at < 0) {
      return;
    }
    final String replaced = "${before.substring(0, at)}@$username ";
    _input.value = TextEditingValue(
      text: replaced + after,
      selection: TextSelection.collapsed(offset: replaced.length),
    );
    setState(() => _suggestions = const <PublicProfile>[]);
  }

  void _startReply(Comment target) {
    // One level deep: replying to a reply answers its top-level review.
    final List<Comment> topLevel = ref.read(commentsControllerProvider(widget.adId)).valueOrNull?.comments ?? const <Comment>[];
    final Comment parent = target.parentId == null
        ? target
        : topLevel.firstWhere((Comment c) => c.id == target.parentId, orElse: () => target);
    setState(() => _replyTo = parent);
    final String? name = target.username;
    if (name != null && _input.text.trim().isEmpty) {
      final String text = "@$name ";
      _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _post() async {
    final String body = _input.text.trim();
    if (body.isEmpty || _posting) {
      return;
    }
    setState(() => _posting = true);
    try {
      await ref.read(commentsControllerProvider(widget.adId).notifier).post(body, parentId: _replyTo?.id);
      _input.clear();
      setState(() {
        _replyTo = null;
        _suggestions = const <PublicProfile>[];
      });
      // Posted: put the keyboard away (it used to stay up).
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).reviewsPostFailed("$e"))));
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<CommentsState> commentsAsync = ref.watch(commentsControllerProvider(widget.adId));

    // Keeps the input row just above the keyboard (see AdVideoCard). Plain
    // padding, not an animated resize — the panel itself doesn't move while
    // typing (it used to hop on every key press).
    final double keyboard = widget.keyboardInset;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(width: 48),
                Expanded(
                  child: Center(
                    child: Text(l10n.actionReviews, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.reviewsClose,
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    widget.onClose();
                  },
                ),
              ],
            ),
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
                data: (CommentsState state) {
                  if (state.comments.isEmpty) {
                    return Center(child: Text(l10n.reviewsEmpty));
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: state.comments.length + (state.isLoadingMore ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= state.comments.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final Comment comment = state.comments[index];
                      final List<Comment>? replies = state.replies[comment.id];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _ReviewRow(adId: widget.adId, comment: comment, onReply: () => _startReply(comment)),
                          if (comment.replyCount > 0 || replies != null)
                            _RepliesToggle(
                              count: comment.replyCount,
                              expanded: replies != null,
                              loading: state.loadingReplies.contains(comment.id),
                              onTap: () {
                                final CommentsController c =
                                    ref.read(commentsControllerProvider(widget.adId).notifier);
                                if (replies != null) {
                                  c.hideReplies(comment.id);
                                } else {
                                  unawaited(c.loadReplies(comment.id).catchError((Object _) {}));
                                }
                              },
                            ),
                          if (replies != null)
                            for (final Comment reply in replies)
                              Padding(
                                padding: const EdgeInsets.only(left: 40),
                                child: _ReviewRow(
                                  adId: widget.adId,
                                  comment: reply,
                                  onReply: () => _startReply(reply),
                                  small: true,
                                ),
                              ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_suggestions.isNotEmpty) _MentionSuggestions(people: _suggestions, onPick: _insertMention),
            if (_replyTo != null)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.reviewsReplyingTo("@${_replyTo!.username ?? l10n.unknownUser}"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.genericCancel,
                      onPressed: _cancelReply,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: _replyTo != null ? l10n.reviewsReplyHint : l10n.reviewsHint,
                        counterText: "",
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _post(),
                      // Tapping the video or the list closes the keyboard.
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ),
                  IconButton(
                    icon: _posting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _posting ? null : _post,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One review or reply: avatar, @author, text with tappable mentions,
/// "Reply", a like (heart + count), and delete (own) / report (others').
class _ReviewRow extends ConsumerWidget {
  const _ReviewRow({required this.adId, required this.comment, required this.onReply, this.small = false});

  final String adId;
  final Comment comment;
  final VoidCallback onReply;
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? currentUserId = ref.watch(currentUserIdProvider);
    final bool isOwn = comment.userId == currentUserId;
    final TextTheme text = Theme.of(context).textTheme;
    // The author's avatar and name open their profile (pushed over the feed).
    final String? username = comment.username;
    void openProfile() {
      if (username != null) {
        unawaited(context.pushTo(RoutePaths.userProfileOf(username)));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: openProfile,
            child: MiniAvatar(avatarUrl: comment.avatarUrl, username: comment.username, size: small ? 26 : 32),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                GestureDetector(
                  onTap: openProfile,
                  child: Text(
                    "@${comment.username ?? l10n.unknownUser}",
                    style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 2),
                MentionText(comment.body, style: text.bodyMedium),
                if (currentUserId != null)
                  TextButton(
                    onPressed: onReply,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                      minimumSize: const Size(48, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(l10n.reviewsReply, style: text.labelMedium),
                  ),
              ],
            ),
          ),
          _LikeButton(adId: adId, comment: comment, enabled: currentUserId != null),
          if (isOwn)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: l10n.genericDelete,
              onPressed: () => unawaited(ref.read(commentsControllerProvider(adId).notifier).deleteOwn(comment)),
            )
          else if (currentUserId != null)
            IconButton(
              icon: const Icon(Icons.flag_outlined, size: 18),
              tooltip: l10n.reportAd,
              onPressed: () => unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (BuildContext context) =>
                      ReportSheet(targetType: ReportTargetType.comment, targetId: comment.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "↳ View 3 replies" / "↳ Hide replies" under a top-level review.
class _RepliesToggle extends StatelessWidget {
  const _RepliesToggle({required this.count, required this.expanded, required this.loading, required this.onTap});

  final int count;
  final bool expanded;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: loading ? null : onTap,
          style: TextButton.styleFrom(minimumSize: const Size(48, 36), padding: EdgeInsets.zero),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.subdirectory_arrow_right, size: 16, color: muted),
              const SizedBox(width: AppSpacing.xs),
              Text(
                expanded ? l10n.reviewsHideReplies : l10n.reviewsViewReplies("$count"),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: muted),
              ),
              if (loading) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Heart + like count on a review (Instagram-style, at the row's end).
/// Liking shows at once; the controller undoes it if the server refuses.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.adId, required this.comment, required this.enabled});

  final String adId;
  final Comment comment;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final bool liked = comment.likedByMe;
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? l10n.reviewUnlike : l10n.reviewLike,
      excludeSemantics: true,
      child: InkResponse(
        radius: 22,
        onTap: !enabled
            ? null
            : () => unawaited(
                  ref.read(commentsControllerProvider(adId).notifier).toggleLike(comment).catchError((Object _) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.reviewLikeFailed)));
                    }
                  }),
                ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: liked ? Colors.redAccent : muted,
              ),
              if (comment.likeCount > 0)
                Text(
                  CountLabel.format(comment.likeCount),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of people to @mention, above the input while typing "@name".
class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({required this.people, required this.onPick});

  final List<PublicProfile> people;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final PublicProfile p = people[index];
          return Center(
            child: ActionChip(
              avatar: MiniAvatar(avatarUrl: p.avatarUrl, username: p.username, size: 24),
              label: Text("@${p.username}"),
              onPressed: () => onPick(p.username),
            ),
          );
        },
      ),
    );
  }
}
