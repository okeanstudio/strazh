import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_nft_decorations.dart';

void main() {
  testWidgets('avatar orbit does not reserve space without equipped gifts', (
    tester,
  ) async {
    const childKey = Key('avatar');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: ProfileNftAvatarOrbit(
            size: 300,
            gifts: [],
            child: SizedBox(key: childKey, width: 120, height: 120),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(childKey)), const Size(120, 120));
    expect(
      tester.getSize(find.byType(ProfileNftAvatarOrbit)),
      const Size(120, 120),
    );
  });
}
