import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_nft_card.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_content_tabs.dart';
import 'package:strazh/shared/domain/models/story.dart';

void main() {
  testWidgets('profile tabs switch between stories and the gift grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileContentTabs(
              stories: [_story()],
              isLoadingStories: false,
              storiesError: null,
              onRetryStories: () {},
              gifts: [
                {'id': 'gift-1', 'gift_name': 'Роза'},
              ],
              isLoadingGifts: false,
              canManageGifts: false,
              onGiftUpgraded: (_) {},
              onGiftPinned: (_) {},
              ownerId: 'owner-1',
              ownerName: 'Denote',
              ownerTag: 'denote',
              ownerAvatarUrl: '',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Публикации 1'), findsOneWidget);
    expect(find.text('Пока нет активных историй'), findsNothing);
    expect(find.byType(GiftNftCard), findsNothing);

    await tester.tap(find.text('Подарки 1'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GiftNftCard), findsOneWidget);
    expect(find.text('Пока нет активных историй'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('profile stories show an empty state and retry on error', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileContentTabs(
            stories: const [],
            isLoadingStories: false,
            storiesError: 'network error',
            onRetryStories: () => retryCount++,
            gifts: const [],
            isLoadingGifts: false,
            canManageGifts: false,
            onGiftUpgraded: (_) {},
            onGiftPinned: (_) {},
            ownerId: 'owner-1',
            ownerName: 'Denote',
            ownerTag: 'denote',
            ownerAvatarUrl: '',
          ),
        ),
      ),
    );

    expect(find.text('Не удалось загрузить публикации'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retryCount, 1);
  });
}

Story _story() => Story(
  id: 'story-1',
  userId: 'owner-1',
  authorName: 'Denote',
  authorTag: 'denote',
  authorAvatarUrl: null,
  text: 'Привет',
  imageUrl: null,
  backgroundColor: '#6C4AB6',
  createdAt: DateTime(2026, 11, 9, 20),
  expiresAt: DateTime(2026, 11, 10, 20),
);
