import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../domain/report_reason.dart";
import "../../domain/report_target_type.dart";
import "../providers/moderation_providers.dart";

/// Report reason picker (CLAUDE.md section 30). One sheet reused for
/// reporting an Ad, a user, or a comment via [targetType].
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({required this.targetType, required this.targetId, super.key});

  final ReportTargetType targetType;
  final String targetId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  bool _submitting = false;

  Future<void> _submit(ReportReason reason) async {
    setState(() => _submitting = true);
    try {
      await ref.read(moderationRepositoryProvider).report(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Thanks — we'll take a look.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't send report: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Text("Report", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (_submitting)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...ReportReason.values.map(
                (ReportReason reason) => ListTile(
                  title: Text(reason.label),
                  onTap: () => unawaited(_submit(reason)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
