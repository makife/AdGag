import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/comment.dart";
import "../providers/comments_controller.dart";

/// REVIEWS bottom sheet (CLAUDE.md section 8). Opened by [ReviewButton].
class ReviewsSheet extends ConsumerStatefulWidget {
  const ReviewsSheet({required this.adId, super.key});

  final String adId;

  @override
  ConsumerState<ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends ConsumerState<ReviewsSheet> {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't post: $e")));
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

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext context, ScrollController sheetScrollController) {
        return Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text("REVIEWS", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
                data: (CommentsState state) {
                  if (state.comments.isEmpty) {
                    return const Center(child: Text("No reviews yet."));
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
                        title: Text("@${comment.username ?? 'unknown'}"),
                        subtitle: Text(comment.body),
                        trailing: isOwn
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => unawaited(
                                  ref
                                      .read(commentsControllerProvider(widget.adId).notifier)
                                      .deleteOwn(comment.id),
                                ),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 500,
                        decoration: const InputDecoration(hintText: "Add a review…", counterText: ""),
                        onSubmitted: (_) => _post(),
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
            ),
          ],
        );
      },
    );
  }
}
