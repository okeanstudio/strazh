import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_chat_item.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_nft_card.dart';

void main() {
  test('NFT upgrade cost is 25 Encoins', () {
    expect(GiftService.nftUpgradeCost, 25);
  });

  test('NFT share links use the Strazh domain and compact gift slug', () {
    expect(
      GiftService.giftNftUrl(name: 'Happy Brownie', serial: 158869),
      'https://strazh.chat/nft/HappyBrownie-158869',
    );
    expect(
      GiftService.giftNftUrl(name: 'Роза', serial: 158869, giftId: 'rose'),
      'https://strazh.chat/nft/rose-158869',
    );
    expect(
      GiftService.giftNftUrl(name: 'Редо', serial: 1, giftId: '1'),
      'https://strazh.chat/nft/redo-1',
    );
    expect(
      GiftService.giftNftUrl(name: 'Роза', serial: 158869),
      'https://strazh.chat/nft/roza-158869',
    );
    expect(GiftService.giftNftUrl(name: 'Роза', serial: null), isNull);
  });

  test('NFT link parser ignores sentence punctuation and other domains', () {
    expect(
      GiftService.giftNftSlugFromUrl(
        'Мой подарок https://strazh.chat/nft/HappyBrownie-158869.',
      ),
      'HappyBrownie-158869',
    );
    expect(
      GiftService.giftNftSlugFromUrl('https://t.me/nft/HappyBrownie-158869'),
      isNull,
    );
    expect(
      GiftService.giftNftSlugFromUrl('https://strazh.chat/nft/bad'),
      isNull,
    );
    expect(
      GiftService.giftNftSlugFromUrl('strazh.chat/nft/HappyBrownie-158869'),
      'HappyBrownie-158869',
    );
  });

  test('NFT card accepts server-owned gift data', () {
    const card = GiftNftCard(gift: {'id': 'inventory-id', 'gift_name': 'Роза'});

    expect(card.gift['id'], 'inventory-id');
  });

  testWidgets('owned gift card exposes a pin action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GiftNftCard(
            gift: {'id': 'inventory-id', 'gift_name': 'Роза'},
            canPin: true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Закрепить в профиле'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile gift animation stops after its preview duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GiftAnimation(
            name: 'Роза',
            size: 80,
            playDuration: Duration(seconds: 2),
          ),
        ),
      ),
    );
    await tester.pump();

    final controller = tester
        .widget<LottieBuilder>(find.byType(LottieBuilder).first)
        .controller!;
    expect(controller.isAnimating, isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(controller.isAnimating, isFalse);
  });

  testWidgets('tapping a gift opens its detail view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GiftNftCard(
              gift: {
                'id': 'inventory-id',
                'gift_name': 'Роза',
                'nft_serial': 17,
                'nft_skin_name': 'Северное сияние',
                'nft_background_color': '#315C91',
                'nft_pattern': 'stars',
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GiftNftCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GiftDetailsDialog), findsOneWidget);
    expect(find.text('Роза #17'), findsOneWidget);
    expect(find.text('Северное сияние'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gift details copies the NFT URL instead of its name', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GiftDetailsDialog(
            gift: {
              'gift_id': 'rose',
              'gift_name': 'Роза',
              'nft_serial': 158869,
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Скопировать ссылку'));
    await tester.pump();

    expect(copiedText, 'https://strazh.chat/nft/rose-158869');
  });

  testWidgets('NFT gift message displays a gift card, not a pasted link', (
    tester,
  ) async {
    final message = Message(
      id: 'gift-message',
      chatId: 'room',
      senderId: 'sender',
      content: 'Подарок: Happy Brownie',
      createdAt: DateTime(2026, 10, 30, 22, 46),
      isMe: true,
      isGift: true,
      giftName: 'Happy Brownie',
      giftNftSerial: 158869,
      giftNftSkinName: 'Frankenstein',
      giftNftBackgroundColor: '#315C91',
      giftNftPattern: 'stars',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GiftChatItem(message: message)),
      ),
    );
    await tester.pump();

    expect(
      find.text('https://strazh.chat/nft/HappyBrownie-158869'),
      findsNothing,
    );
    expect(find.text('Вы отправили подарок'), findsOneWidget);
    expect(find.text('Посмотреть'), findsOneWidget);
    expect(find.text('Happy Brownie #158869'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gift message says when the current user received it', (
    tester,
  ) async {
    final message = Message(
      id: 'received-gift',
      chatId: 'room',
      senderId: 'other-user',
      content: 'Подарок: Роза',
      createdAt: DateTime(2026, 10, 31, 12),
      isMe: false,
      isGift: true,
      giftName: 'Роза',
      giftPriceEnc: 25,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GiftChatItem(
            message: message.copyWith(
              sender: const app.User(
                id: 'other-user',
                name: 'denote',
                tag: 'denote',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Вы получили подарок стоимостью 25 ENC'), findsOneWidget);
    expect(find.text('Подарок от denote'), findsOneWidget);
    expect(find.text('Посмотреть'), findsOneWidget);
  });

  testWidgets('gift message says when the current user sent it', (
    tester,
  ) async {
    final message = Message(
      id: 'sent-gift',
      chatId: 'room',
      senderId: 'current-user',
      content: 'Подарок: Роза',
      createdAt: DateTime(2026, 10, 31, 12),
      isMe: true,
      isGift: true,
      giftName: 'Роза',
      giftPriceEnc: 25,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GiftChatItem(message: message)),
      ),
    );

    expect(find.text('Вы отправили подарок стоимостью 25 ENC'), findsOneWidget);
  });

  testWidgets('owned gift card exposes a pin action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GiftNftCard(
            gift: {'id': 'inventory-id', 'gift_name': 'Роза'},
            canPin: true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Закрепить в профиле'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile NFT upgrade roulette visibly moves', (tester) async {
    Future<void> pumpRoulette(double progress, {String? winningSkinName}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: GiftCaseRoulette(
                  progress: progress,
                  winningSkinName: winningSkinName,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpRoulette(0);
    final track = find.byKey(const ValueKey('profile-gift-roulette-track'));
    final initialOffset = tester.widget<Transform>(track).transform.storage[12];

    await pumpRoulette(0.5);
    final movedOffset = tester.widget<Transform>(track).transform.storage[12];

    expect(movedOffset, isNot(initialOffset));

    await pumpRoulette(4.75, winningSkinName: 'Мятный блеск');
    final rouletteRect = tester.getRect(find.byType(GiftCaseRoulette));
    final winningCardRect = tester.getRect(
      find.byKey(const ValueKey('profile-gift-roulette-winning-item')),
    );
    expect(winningCardRect.center.dx, closeTo(rouletteRect.center.dx, 2));
    expect(tester.takeException(), isNull);
  });
}
