import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_content_tabs.dart';
import 'package:strazh/shared/domain/models/story.dart';

void main() {
  testWidgets(
    'expired publications remain visible in profile without expiry label',
    (tester) async {
      final expiredStory = Story(
        id: 'expired-story',
        userId: 'user-1',
        authorName: 'Алексей',
        authorTag: 'alex',
        authorAvatarUrl: null,
        text: 'Старая публикация',
        imageUrl: null,
        backgroundColor: '#6C4AB6',
        createdAt: DateTime.utc(2020),
        expiresAt: DateTime.utc(2020, 1, 2),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileContentTabs(
              stories: [expiredStory],
              isLoadingStories: false,
              storiesError: null,
              onRetryStories: () {},
              gifts: const [],
              isLoadingGifts: false,
              canManageGifts: false,
              onGiftUpgraded: (_) {},
              onGiftPinned: (_) {},
              ownerId: 'user-1',
              ownerName: 'Алексей',
              ownerTag: 'alex',
              ownerAvatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('Старая публикация'), findsOneWidget);
      expect(find.text('Истекла'), findsNothing);
      expect(find.text('Публикации 1'), findsOneWidget);
    },
  );

  testWidgets('tapping an older publication opens that publication first', (
    tester,
  ) async {
    final oldStory = Story(
      id: 'old-story',
      userId: 'user-1',
      authorName: 'Алексей',
      authorTag: 'alex',
      authorAvatarUrl: null,
      text: 'Старая публикация',
      imageUrl: null,
      backgroundColor: '#6C4AB6',
      createdAt: DateTime.utc(2020),
      expiresAt: DateTime.utc(2020, 1, 2),
    );
    final newStory = Story(
      id: 'new-story',
      userId: 'user-1',
      authorName: 'Алексей',
      authorTag: 'alex',
      authorAvatarUrl: null,
      text: 'Новая публикация',
      imageUrl: null,
      backgroundColor: '#168C83',
      createdAt: DateTime.utc(2021),
      expiresAt: DateTime.utc(2021, 1, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileContentTabs(
            stories: [oldStory, newStory],
            isLoadingStories: false,
            storiesError: null,
            onRetryStories: () {},
            gifts: const [],
            isLoadingGifts: false,
            canManageGifts: false,
            onGiftUpgraded: (_) {},
            onGiftPinned: (_) {},
            ownerId: 'user-1',
            ownerName: 'Алексей',
            ownerTag: 'alex',
            ownerAvatarUrl: '',
          ),
        ),
      ),
    );

    await tester.tap(find.text('Старая публикация'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Старая публикация'), findsNWidgets(2));
    expect(find.text('Новая публикация'), findsOneWidget);
  });
}
