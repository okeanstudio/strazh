import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/presentation/widgets/username_mention_text.dart';

void main() {
  test('username list uses one "also" and comma-separated aliases', () {
    expect(
      formatUsernameList('@admin', ['@dev', 'support', 'DEV']),
      '@admin также @dev, @support',
    );
  });

  testWidgets('username mentions are tappable and preserve surrounding text', (
    tester,
  ) async {
    String? tappedUsername;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsernameMentionText(
            text: 'Напиши @dev, потом @support!',
            style: const TextStyle(),
            linkColor: Colors.blue,
            onUsernameTap: (username) => tappedUsername = username,
          ),
        ),
      ),
    );

    final richTextFinder = find.byType(RichText);
    final richText = tester.widget<RichText>(richTextFinder);
    expect(richText.text.toPlainText(), 'Напиши @dev, потом @support!');

    final textPainter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: tester.getSize(richTextFinder).width);
    final mentionOffset = textPainter.getOffsetForCaret(
      TextPosition(offset: richText.text.toPlainText().indexOf('@support') + 2),
      Rect.zero,
    );
    final tapPosition =
        tester.getTopLeft(richTextFinder) +
        mentionOffset +
        Offset(1, textPainter.preferredLineHeight / 2);
    await tester.tapAt(tapPosition);
    await tester.pump();

    expect(tappedUsername, 'support');
  });

  testWidgets('slash commands are underlined and tappable', (tester) async {
    String? tappedCommand;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsernameMentionText(
            text: 'Нажми /start чтобы начать.',
            style: const TextStyle(),
            linkColor: Colors.blue,
            onUsernameTap: (_) {},
            onCommandTap: (command) => tappedCommand = command,
          ),
        ),
      ),
    );

    final richTextFinder = find.byType(RichText);
    final richText = tester.widget<RichText>(richTextFinder);
    expect(richText.text.toPlainText(), 'Нажми /start чтобы начать.');
    final commandSpan = (richText.text as TextSpan).children!
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == '/start');
    expect(commandSpan.style?.decoration, TextDecoration.underline);

    final textPainter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: tester.getSize(richTextFinder).width);
    final commandOffset = textPainter.getOffsetForCaret(
      TextPosition(offset: richText.text.toPlainText().indexOf('/start') + 2),
      Rect.zero,
    );
    final tapPosition =
        tester.getTopLeft(richTextFinder) +
        commandOffset +
        Offset(1, textPainter.preferredLineHeight / 2);
    await tester.tapAt(tapPosition);
    await tester.pump();

    expect(tappedCommand, '/start');
  });
}
