import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
import "../providers/create_ad_flow_controller.dart";

/// "What are you selling today?" (CLAUDE.md section 12/38). Free-text
/// entry resolved server-side via `get_or_create_ad_subject` — no
/// client-side subject search yet (that's Market/Discovery, Phase F); for
/// MVP the user either matches an existing subject exactly or creates one.
class SubjectPickerStep extends ConsumerStatefulWidget {
  const SubjectPickerStep({super.key});

  @override
  ConsumerState<SubjectPickerStep> createState() => _SubjectPickerStepState();
}

class _SubjectPickerStepState extends ConsumerState<SubjectPickerStep> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(createAdFlowControllerProvider.notifier).selectSubjectText(text);
    } catch (e) {
      setState(() => _error = "$e");
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("What are you selling today?")),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: "Rock, coffee, Monday, yourself…"),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Next"),
            ),
          ],
        ),
      ),
    );
  }
}
