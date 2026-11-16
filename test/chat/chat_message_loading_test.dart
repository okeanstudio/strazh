import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_message_loading.dart';

void main() {
  testWidgets('message loading shows animated empty bubble shapes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: ChatMessageLoading()),
        ),
      ),
    );

    expect(find.byType(ChatMessageLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('messages fade and slide into view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatMessageEntrance(child: Text('Сообщение'))),
      ),
    );

    final entranceFade = find.descendant(
      of: find.byType(ChatMessageEntrance),
      matching: find.byType(FadeTransition),
    );
    expect(entranceFade, findsOneWidget);
    expect(
      tester.widget<FadeTransition>(entranceFade).opacity.value,
      lessThan(1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FadeTransition>(entranceFade).opacity.value,
      closeTo(1, 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}
