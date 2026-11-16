import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/features/chat/data/services/chat_list_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores chat actions separately for each account', () async {
    final firstAccount = (await ChatListPreferences.load(
      'user-one',
      synchronize: false,
    ))!;
    await firstAccount.setPinned('room-one', true);
    await firstAccount.setArchived('room-two', true);
    await firstAccount.setMuted('room-three', true);

    final secondAccount = (await ChatListPreferences.load(
      'user-two',
      synchronize: false,
    ))!;
    expect(secondAccount.pinnedChatIds, isEmpty);
    expect(secondAccount.archivedChatIds, isEmpty);
    expect(secondAccount.mutedChatIds, isEmpty);

    final restoredAccount = (await ChatListPreferences.load(
      'user-one',
      synchronize: false,
    ))!;
    expect(restoredAccount.pinnedChatIds, {'room-one'});
    expect(restoredAccount.archivedChatIds, {'room-two'});
    expect(restoredAccount.mutedChatIds, {'room-three'});
  });

  test('mute lookup uses the currently loaded account', () async {
    final firstAccount = (await ChatListPreferences.load(
      'user-one',
      synchronize: false,
    ))!;
    await firstAccount.setMuted('room-one', true);
    expect(await ChatListPreferences.isMutedForCurrentUser('room-one'), isTrue);

    await ChatListPreferences.load('user-two', synchronize: false);
    expect(
      await ChatListPreferences.isMutedForCurrentUser('room-one'),
      isFalse,
    );
  });

  test(
    'folders and chat assignments persist separately for each account',
    () async {
      final firstAccount = (await ChatListPreferences.load(
        'user-one',
        synchronize: false,
      ))!;
      await firstAccount.createFolder('Работа');
      await firstAccount.createFolder('Друзья');
      await firstAccount.setChatFolder('room-one', 'Работа');

      final secondAccount = (await ChatListPreferences.load(
        'user-two',
        synchronize: false,
      ))!;
      expect(secondAccount.folderNames, isEmpty);
      expect(secondAccount.folderByChatId, isEmpty);

      final restoredAccount = (await ChatListPreferences.load(
        'user-one',
        synchronize: false,
      ))!;
      expect(restoredAccount.folderNames, {'Работа', 'Друзья'});
      expect(restoredAccount.folderByChatId, {'room-one': 'Работа'});

      await restoredAccount.deleteFolder('Работа');
      expect(restoredAccount.folderNames, {'Друзья'});
      expect(restoredAccount.folderByChatId, isEmpty);

      final afterDelete = (await ChatListPreferences.load(
        'user-one',
        synchronize: false,
      ))!;
      expect(afterDelete.folderNames, {'Друзья'});
      expect(afterDelete.folderByChatId, isEmpty);
    },
  );

  test(
    'folder names are validated and case-insensitive duplicates rejected',
    () async {
      final preferences = (await ChatListPreferences.load(
        'user-one',
        synchronize: false,
      ))!;
      await preferences.createFolder('Работа');

      await expectLater(
        preferences.createFolder(' работа '),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        preferences.createFolder(' '),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
