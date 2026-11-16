import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:strazh/shared/domain/models/gift.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_chat_item.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_case_reveal_dialog.dart';

void main() {
  testWidgets('gift animation asset parses as a Lottie composition', (
    tester,
  ) async {
    final data = await rootBundle.load('assets/gifts/gift_box.json');
    final composition = await LottieComposition.fromByteData(data);

    expect(composition.duration, greaterThan(Duration.zero));
    expect(composition.layers, isNotEmpty);
  });

  test('gift animation resolves by catalog id or localized name', () {
    expect(
      giftAnimationAssetPath(name: 'Роза', giftId: 'rose'),
      'assets/gifts/rose.json',
    );
    expect(
      giftAnimationAssetPath(name: 'Мишка', giftId: 'catalog-item-4'),
      'assets/gifts/teddy.json',
    );
    expect(
      giftAnimationAssetPath(name: 'Crown', giftId: 'unknown'),
      'assets/gifts/crown.json',
    );
  });

  test('gift catalog entries can include a remote animation URL', () {
    final gift = Gift.fromJson({
      'id': 'casino',
      'name': 'Казино',
      'emoji': '🎰',
      'price_enc': 500,
      'animation_url':
          'https://example.supabase.co/storage/v1/object/public/gifts/casino.json',
    });

    expect(gift.animationUrl, contains('/gifts/casino.json'));
  });

  testWidgets('gift card plays its Lottie animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedGiftCard(name: 'Мишка')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Мишка'), findsOneWidget);
    expect(find.text('🧸'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gift case reveal stops on the upgraded gift', (tester) async {
    final result = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: GiftCaseRevealDialog(
          name: 'Роза',
          giftId: '',
          emoji: '🌹',
          result: result.future,
        ),
      ),
    );

    expect(find.text('ОТКРЫВАЕМ ПОДАРОК'), findsOneWidget);
    final rouletteTrack = find.byKey(
      const ValueKey('gift-case-roulette-track'),
    );
    final startPosition = tester
        .widget<Transform>(rouletteTrack)
        .transform
        .storage[12];
    await tester.pump(const Duration(milliseconds: 500));
    final currentPosition = tester
        .widget<Transform>(rouletteTrack)
        .transform
        .storage[12];
    expect(currentPosition, isNot(startPosition));

    result.complete({
      'nft_skin_name': 'Мятный блеск',
      'nft_skin_emoji': '❄️',
      'nft_serial': 42,
      'nft_background_color': '#28756B',
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();

    expect(find.text('ПОДАРОК УЛУЧШЕН!'), findsOneWidget);
    expect(find.text('№ 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('legacy gift messages are recognized without the is_gift flag', () {
    expect(
      Message.isGiftMessage({'encrypted_content': 'Подарок: Роза'}),
      isTrue,
    );
    expect(Message.giftNameFromContent('Подарок: Роза'), 'Роза');
    expect(Message.giftNameFromContent('  подарок: Торт  '), 'Торт');
    expect(Message.giftNameFromContent('Обычное сообщение'), isNull);
  });

  test('copying a chat message preserves all gift fields', () {
    final message = Message(
      id: 'gift-message',
      chatId: 'chat',
      senderId: 'sender',
      content: 'Подарок: Бриллиант',
      createdAt: DateTime(2026),
      isMe: false,
      isGift: true,
      giftName: 'Бриллиант',
      giftId: 'diamond',
      giftEmoji: '💎',
      giftPriceEnc: 250,
      giftCaption: 'Для тебя',
      giftNftSerial: 158869,
      giftNftSkinName: 'Frankenstein',
      giftNftSkinEmoji: '🧟',
      giftNftBackgroundColor: '#315C91',
      giftNftPattern: 'stars',
      giftNftAnimationUrl: 'https://strazh.chat/gifts/frankenstein.json',
    );

    final displayed = message.copyWith(readByOthers: true);

    expect(displayed.isGift, isTrue);
    expect(displayed.giftName, 'Бриллиант');
    expect(displayed.giftId, 'diamond');
    expect(displayed.giftEmoji, '💎');
    expect(displayed.giftPriceEnc, 250);
    expect(displayed.giftCaption, 'Для тебя');
    expect(displayed.giftNftSerial, 158869);
    expect(displayed.giftNftSkinName, 'Frankenstein');
    expect(displayed.giftNftSkinEmoji, '🧟');
    expect(displayed.giftNftBackgroundColor, '#315C91');
    expect(displayed.giftNftPattern, 'stars');
    expect(
      displayed.giftNftAnimationUrl,
      'https://strazh.chat/gifts/frankenstein.json',
    );
  });

  testWidgets('long pressing a gift chat item starts message selection', (
    tester,
  ) async {
    var selectionStarted = false;
    final message = Message(
      id: 'gift-message',
      chatId: 'chat',
      senderId: 'sender',
      content: 'Подарок: Бриллиант',
      createdAt: DateTime(2026),
      isMe: false,
      isGift: true,
      giftName: 'Бриллиант',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GiftChatItem(
            message: message,
            onLongPress: () => selectionStarted = true,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(GiftChatItem));

    expect(selectionStarted, isTrue);
  });
}
