import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

String formatUsernameList(String primary, Iterable<String> additional) {
  String clean(String username) =>
      username.trim().replaceFirst(RegExp(r'^@+'), '');

  final primaryUsername = clean(primary);
  if (primaryUsername.isEmpty) return '';

  final seen = {primaryUsername.toLowerCase()};
  final additionalUsernames = <String>[];
  for (final username in additional) {
    final cleaned = clean(username);
    if (cleaned.isNotEmpty && seen.add(cleaned.toLowerCase())) {
      additionalUsernames.add(cleaned);
    }
  }

  if (additionalUsernames.isEmpty) return '@$primaryUsername';
  return '@$primaryUsername также ${additionalUsernames.map((username) => '@$username').join(', ')}';
}

class UsernameMentionText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final ValueChanged<String>? onUsernameTap;
  final ValueChanged<String>? onUrlTap;
  final ValueChanged<String>? onCommandTap;
  final TextAlign textAlign;

  const UsernameMentionText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    required this.onUsernameTap,
    this.onUrlTap,
    this.onCommandTap,
    this.textAlign = TextAlign.start,
  });

  @override
  State<UsernameMentionText> createState() => _UsernameMentionTextState();
}

class _UsernameMentionTextState extends State<UsernameMentionText> {
  static final RegExp _linkRegex = RegExp(
    r'(https?://[^\s]+)|(www\.[^\s]+)|([a-zA-Z0-9-]+\.[a-zA-Z]{2,}[^\s]*)|(?<![\w@])@([a-zA-Z0-9_]{3,})|(?<![\w/])(/[a-zA-Z][a-zA-Z0-9_]{0,31}(?:@[a-zA-Z0-9_]{3,})?)',
    caseSensitive: false,
  );
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (final match in _linkRegex.allMatches(widget.text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: widget.text.substring(lastEnd, match.start)));
      }

      final mention = match.group(4);
      final command = match.group(5);
      if (mention != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = widget.onUsernameTap == null
              ? null
              : () => widget.onUsernameTap!(mention);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: match.group(0),
            style: TextStyle(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      } else if (command != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = widget.onCommandTap == null
              ? null
              : () => widget.onCommandTap!(command);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: command,
            style: TextStyle(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      } else {
        var url = match.group(0)!;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
        }
        final recognizer = TapGestureRecognizer()
          ..onTap = widget.onUrlTap == null
              ? null
              : () => widget.onUrlTap!(url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: match.group(0),
            style: TextStyle(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastEnd)));
    }

    return RichText(
      textAlign: widget.textAlign,
      text: TextSpan(style: widget.style, children: spans),
    );
  }
}
