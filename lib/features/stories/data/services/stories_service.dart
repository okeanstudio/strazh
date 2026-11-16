import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/core/utils/subscription_utils.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class StoriesService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ValueNotifier<int> storiesRevision = ValueNotifier(0);

  static bool get canPublish {
    return isPremiumSubscriptionActive(
      _supabase.auth.currentUser?.userMetadata,
    );
  }

  static Future<bool> refreshPublishAccess() async {
    if (_supabase.auth.currentUser == null) return false;
    await _supabase.auth.refreshSession();
    return canPublish;
  }

  static Future<List<Story>> getActiveStories() async {
    try {
      final response = await _supabase
          .from('stories')
          .select()
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      final stories = response
          .map((row) => Story.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      return await _attachSignedImageUrls(stories, activeOnly: true);
    } catch (error) {
      debugPrint('Не удалось загрузить истории: $error');
      rethrow;
    }
  }

  static Future<List<Story>> getProfileStories(String userId) async {
    try {
      final response = await _supabase
          .from('stories')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final stories = response
          .map((row) => Story.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      return await _attachSignedImageUrls(stories, activeOnly: false);
    } catch (error) {
      debugPrint('Не удалось загрузить публикации профиля: $error');
      rethrow;
    }
  }

  static Future<List<Story>> _attachSignedImageUrls(
    List<Story> stories, {
    required bool activeOnly,
  }) async {
    return Future.wait(
      stories.map((story) async {
        final imagePath = story.imageUrl;
        if (imagePath == null) return story;

        final expiresIn = activeOnly
            ? story.expiresAt
                  .difference(DateTime.now())
                  .inSeconds
                  .clamp(1, 86400)
                  .toInt()
            : 86400;
        final signedUrl = await StorageUploadService.createSignedUrl(
          bucket: 'stories',
          path: imagePath,
          expiresIn: expiresIn,
        );
        return story.withImageUrl(signedUrl);
      }),
    );
  }

  static Future<void> publish({
    required String text,
    required String backgroundColor,
    required double textPositionX,
    required double textPositionY,
    XFile? image,
  }) async {
    try {
      String? imageUrl;
      if (image != null) {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) {
          throw StateError('Для публикации истории нужно войти в аккаунт');
        }

        final fileName = image.name.toLowerCase();
        final sourceExtension = fileName.contains('.')
            ? fileName.split('.').last
            : 'jpg';
        final extension = switch (sourceExtension) {
          'png' || 'webp' || 'heic' || 'jpeg' || 'jpg' => sourceExtension,
          'heif' => 'heic',
          _ => 'jpg',
        };
        final contentType = switch (extension) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          'heic' => 'image/heic',
          'jpeg' || 'jpg' => 'image/jpeg',
          _ => 'image/jpeg',
        };
        final path =
            '$userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
        await StorageUploadService.uploadBinary(
          bucket: 'stories',
          path: path,
          bytes: await image.readAsBytes(),
          contentType: contentType,
          onProgress: (_, _) {},
        );
        imageUrl = path;
      }

      await _supabase.rpc(
        'create_text_story',
        params: {
          'p_content': text,
          'p_background_color': backgroundColor,
          'p_image_url': imageUrl,
          'p_text_position_x': textPositionX,
          'p_text_position_y': textPositionY,
        },
      );
      storiesRevision.value++;
    } catch (error) {
      debugPrint('Не удалось опубликовать историю: $error');
      rethrow;
    }
  }
}
