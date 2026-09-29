import "dart:async" show unawaited;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";

import "../../core/router/route_paths.dart";

/// Review text with every `@username` bold and tappable (opens that
/// profile). Matches the server's mention rule
/// (0022_following_feed_replies_mentions.sql) and the username format.
class MentionText extends StatefulWidget {
  const MentionText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  static final RegExp pattern = RegExp(r"@([A-Za-z][A-Za-z0-9_]{2,19})");

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final String text = widget.text;
    final List<InlineSpan> spans = <InlineSpan>[];
    int last = 0;
    for (final RegExpMatch m in MentionText.pattern.allMatches(text)) {
      // "x@name" (an email, say) is not a mention.
      if (m.start > 0 && RegExp(r"[A-Za-z0-9_]").hasMatch(text[m.start - 1])) {
        continue;
      }
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final String username = m.group(1)!.toLowerCase();
      final TapGestureRecognizer recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(context.pushTo(RoutePaths.userProfileOf(username)));
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(fontWeight: FontWeight.w700),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
