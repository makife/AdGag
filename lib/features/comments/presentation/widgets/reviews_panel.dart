import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../../core/localization/generated/app_localizations.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/mini_avatar.dart";
import "../../domain/comment.dart";
import "../providers/comments_controller.dart";

/// REVIEWS panel (CLAUDE.md section 8). Shown INSIDE the feed card under a
/// shrunken video (not a modal over it — user request: the video should
/// stay visible, smaller, while reading reviews). See AdVideoCard.
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
  final ScrollController _scroll = ScrollController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
        unawaited(ref.read(commentsControllerProvider(widget.adId).notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final String body = _input.text.trim();
    if (body.isEmpty || _posting) {
      return;
    }
    setState(() => _posting = true);
    try {
      await ref.read(commentsControllerProvider(widget.adId).notifier).post(body);
      _input.clear();
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
    final AsyncValue<CommentsState> commentsAsync = ref.watch(commentsControllerProvider(widget.adId));
    final String? currentUserId = ref.watch(currentUserIdProvider);

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
                    child: Text(AppLocalizations.of(context).actionReviews,
                        style: const TextStyle(fontWeight: FontWeight.w700),),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: AppLocalizations.of(context).reviewsClose,
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
                    return Center(child: Text(AppLocalizations.of(context).reviewsEmpty));
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
                      final bool isOwn = comment.userId == currentUserId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: MiniAvatar(avatarUrl: comment.avatarUrl, username: comment.username, size: 32),
                        title: Text("@${comment.username ?? AppLocalizations.of(context).unknownUser}"),
                        subtitle: Text(comment.body),
                        trailing: isOwn
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => unawaited(
                                  ref.read(commentsControllerProvider(widget.adId).notifier).deleteOwn(comment.id),
                                ),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 500,
                      decoration: InputDecoration(hintText: AppLocalizations.of(context).reviewsHint, counterText: ""),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _post(),
                      // Tapping the video or the list closes the keyboard.
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ),
                  IconButton(
                    icon: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
