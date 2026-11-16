import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

// ВНИМАНИЕ: Чтобы этот файл работал, в pubspec.yaml должен быть:
// image_picker: ^1.1.2 (если ты хочешь выбирать файлы)
// Сейчас мы сделаем его без image_picker, используя просто путь к файлу

Future<String?> uploadAvatar({required String filePath}) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('Файл не найден: $filePath');
      return null;
    }
    
    const storage = FlutterSecureStorage();
    final userId = await storage.read(key: 'user_id');
    final userTag = await storage.read(key: 'user_tag');
    
    if (userId == null || userTag == null) return null;
    
    final fileName = 'avatars/$userId.jpg';
    
    final bytes = await file.readAsBytes();
    final authenticatedUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authenticatedUserId == null) return null;
    final objectPath = '$authenticatedUserId/${fileName.split('/').last}';
    await StorageUploadService.uploadBinary(
      bucket: 'avatars',
      path: objectPath,
      bytes: bytes,
      contentType: 'image/jpeg',
      onProgress: (_, _) {},
    );

    final imageUrl = await StorageUploadService.getPublicUrl(
      bucket: 'avatars',
      path: objectPath,
    );
    
    // Обновляем URL в Supabase Auth метаданных
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (e) {
        debugPrint('⚠️ Не удалось обновить сессию: $e');
      }

      final metadata = user.userMetadata ?? {};
      metadata['avatar_url'] = imageUrl;
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadata),
      );
    }
    
    debugPrint('Аватарка загружена: $imageUrl');
    return imageUrl;
  } catch (e) {
    debugPrint('Ошибка загрузки: $e');
    return null;
  }
}