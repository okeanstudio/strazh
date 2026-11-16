import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class AvatarService {
  static final supabase = Supabase.instance.client;

  // Выбор фото из галереи или камеры
  static Future<XFile?> pickImage({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
  }) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return null;
    return cropImage(image, context: context);
  }

  // Загрузка аватарки на сервер
  static Future<String?> uploadAvatar({
    required XFile image,
    required String userId,
    VoidCallback? onProgress,
  }) async {
    try {
      debugPrint('📤 Начинаем загрузку аватарки для пользователя: $userId');
      final bytes = await image.readAsBytes();
      final extension = image.path.split('.').last.toLowerCase();
      final safeExtension = extension.isEmpty ? 'jpg' : extension;
      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

      debugPrint('📦 Размер файла: ${bytes.length} байт, тип: $safeExtension');
      debugPrint('📝 Путь файла: $fileName');
      try {
        debugPrint('🚀 Отправка файла в Storage...');
        await StorageUploadService.uploadBinary(
          bucket: 'avatars',
          path: fileName,
          bytes: bytes,
          contentType: safeExtension == 'png' ? 'image/png' : 'image/jpeg',
          onProgress: (_, _) {},
        );
      } on SocketException catch (e) {
        debugPrint('❌ Ошибка сокета при загрузке: $e');
        debugPrint('📋 Код ошибки: ${e.osError?.errorCode}');
        debugPrint('📋 Сообщение ОС: ${e.osError?.message}');
        return null;
      } catch (e) {
        debugPrint('❌ Ошибка загрузки файла: $e');
        debugPrint('📋 Тип ошибки: ${e.runtimeType}');
        debugPrint('📋 Stack trace: ${StackTrace.current}');
        rethrow;
      }

      final publicUrl = await StorageUploadService.getPublicUrl(
        bucket: 'avatars',
        path: fileName,
      );
      debugPrint('🔗 Получен публичный URL: $publicUrl');

      // Обновляем URL в Supabase Auth метаданных
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase.auth.refreshSession();
          debugPrint('🔄 Сессия обновлена');
        } catch (e) {
          debugPrint('⚠️ Не удалось обновить сессию: $e');
        }

        final metadata = user.userMetadata ?? {};
        metadata['avatar_url'] = publicUrl;
        try {
          await supabase.auth.updateUser(
            UserAttributes(data: metadata),
          );
          debugPrint('✅ Метаданные пользователя обновлены');
        } catch (e) {
          debugPrint('⚠️ Не удалось обновить метаданные: $e');
        }
      }

      return publicUrl;
    } catch (e) {
      debugPrint('❌ Ошибка загрузки аватарки: $e');
      debugPrint('📋 Тип ошибки: ${e.runtimeType}');
      
      if (e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
        debugPrint('⚠️ Проблема с сертификатом SSL/TLS:');
        debugPrint('   - Проверьте что сертификаты сервера правильно установлены');
        debugPrint('   - Убедитесь что цепочка сертификатов полная');
        debugPrint('   - Проверьте что домен совпадает с сертификатом');
      }
      if (e.toString().contains('Handshake')) {
        debugPrint('⚠️ Ошибка при рукопожатии SSL/TLS');
      }
      return null;
    }
  }

  // Удаление аватарки (сброс на дефолтную)
  static Future<bool> deleteAvatar(String userId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase.auth.refreshSession();
        } catch (e) {
          debugPrint('⚠️ Не удалось обновить сессию: $e');
        }

        final metadata = user.userMetadata ?? {};
        metadata['avatar_url'] = null;
        await supabase.auth.updateUser(
          UserAttributes(data: metadata),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Ошибка удаления аватарки: $e');
      return false;
    }
  }

  // Обрезка изображения (опционально)
  static Future<XFile?> cropImage(
    XFile image, {
    required BuildContext context,
  }) async {
    final platform = defaultTargetPlatform;
    if (!kIsWeb &&
        platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS) {
      return image;
    }

    final settings = <PlatformUiSettings>[
      if (platform == TargetPlatform.android)
        AndroidUiSettings(
          toolbarTitle: 'Обрезать фото',
          toolbarColor: const Color(0xFF1A1428),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF6C9EFF),
          cropStyle: CropStyle.circle,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      if (platform == TargetPlatform.iOS)
        IOSUiSettings(
          title: 'Обрезать фото',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      if (kIsWeb) WebUiSettings(context: context),
    ];

    final cropped = await ImageCropper().cropImage(
      sourcePath: image.path,
      maxWidth: 512,
      maxHeight: 512,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: settings,
    );
    return cropped == null ? null : XFile(cropped.path);
  }
}