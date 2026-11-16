import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

void main() {
  testWidgets('renders the animated Strazh S without a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0D0A0A),
          body: Center(child: StrazhSLoader(label: 'Загрузка')),
        ),
      ),
    );

    expect(find.text('S'), findsNWidgets(9));
    expect(find.text('Загрузка'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
}
