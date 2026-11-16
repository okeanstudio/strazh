import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/gift.dart';

class GiftService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final Map<String, Future<String?>> _animationUrlCache = {};
  static final Map<String, Future<Map<String, dynamic>>> _nftDetailsCache = {};
  static Future<List<Map<String, dynamic>>>? _animationCatalog;
  static const int nftUpgradeCost = 25;

  static String? get currentUserId => _supabase.auth.currentUser?.id;

  static String? giftNftUrl({
    required String name,
    required int? serial,
    String? giftId,
  }) {
    if (serial == null || serial < 1) return null;
    final nameSlug = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final idSlug = (giftId ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final slug = nameSlug.isNotEmpty
        ? nameSlug
        : RegExp(r'[A-Za-z]').hasMatch(idSlug)
        ? idSlug
        : _transliterateGiftName(name);
    if (slug.isEmpty) return null;
    return 'https://strazh.chat/nft/$slug-$serial';
  }

  static String _transliterateGiftName(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'ё': 'yo',
      'ж': 'zh',
      'х': 'kh',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'shch',
      'ъ': '',
      'ь': '',
      'ю': 'yu',
      'я': 'ya',
    };
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    const letters = {
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'ы': 'y',
      'э': 'e',
    };
    result = String.fromCharCodes(
      result.runes.map((rune) {
        final replacement = letters[String.fromCharCode(rune)];
        return replacement == null ? rune : replacement.codeUnitAt(0);
      }),
    );
    return result.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  }

  static String? giftNftSlugFromUrl(String value) {
    final match = RegExp(
      r'(?<![A-Za-z0-9.-])(?:https?://)?strazh\.chat/nft/([A-Za-z0-9]+-[0-9]+)(?=$|[\s/?#.,!?;:)\]])',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1);
  }

  static Future<List<Gift>> getCatalog() async {
    final rows = await _supabase
        .from('gift_catalog')
        .select('id, name, emoji, price_enc, animation_url')
        .eq('is_active', true)
        .order('sort_order');
    return rows
        .map((row) => Gift.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<String?> getAnimationUrl({
    required String name,
    String? giftId,
  }) async {
    final trimmedId = giftId?.trim();
    final id = trimmedId == null || trimmedId.isEmpty ? null : trimmedId;
    final normalizedName = name.trim().toLowerCase();
    final cacheKey = id != null && id.isNotEmpty
        ? 'id:$id'
        : 'name:$normalizedName';
    final pending = _animationUrlCache.putIfAbsent(
      cacheKey,
      () => _findAnimationUrl(id: id, normalizedName: normalizedName),
    );
    try {
      return await pending;
    } catch (_) {
      if (identical(_animationUrlCache[cacheKey], pending)) {
        _animationUrlCache.remove(cacheKey);
      }
      rethrow;
    }
  }

  static Future<String?> _findAnimationUrl({
    required String? id,
    required String normalizedName,
  }) async {
    final rows = await _getAnimationCatalog();
    for (final row in rows) {
      final matchesId = id != null && row['id'] == id;
      final matchesName =
          id == null &&
          row['name'].toString().trim().toLowerCase() == normalizedName;
      if (matchesId || matchesName) {
        final url = row['animation_url']?.toString().trim();
        return url == null || url.isEmpty ? null : url;
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _getAnimationCatalog() async {
    final cached = _animationCatalog;
    if (cached != null) return cached;

    final request = _supabase
        .from('gift_catalog')
        .select('id, name, animation_url')
        .eq('is_active', true)
        .then(
          (rows) => rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        );
    _animationCatalog = request;
    try {
      return await request;
    } catch (_) {
      if (identical(_animationCatalog, request)) {
        _animationCatalog = null;
      }
      rethrow;
    }
  }

  static void clearAnimationUrlCache() {
    _animationUrlCache.clear();
    _animationCatalog = null;
  }

  static Future<Map<String, dynamic>> sendGift({
    required String roomId,
    required Gift gift,
    String caption = '',
    bool upgradeToNft = false,
  }) async {
    final response = await _supabase.rpc(
      upgradeToNft ? 'send_gift_with_upgrade' : 'send_gift',
      params: {'p_room_id': roomId, 'p_gift_id': gift.id, 'p_caption': caption},
    );
    if (response is! Map) {
      throw const FormatException('Некорректный ответ при отправке подарка');
    }
    return Map<String, dynamic>.from(response);
  }

  static Future<void> grantGift({
    required String userId,
    required Gift gift,
    String caption = '',
  }) async {
    await _supabase.rpc(
      'grant_gift_admin',
      params: {'p_user_id': userId, 'p_gift_id': gift.id, 'p_caption': caption},
    );
  }

  static Future<List<Map<String, dynamic>>> getAdminUserGifts(
    String userId,
  ) async {
    final response = await _supabase.rpc(
      'get_admin_user_gifts',
      params: {'p_user_id': userId},
    );
    if (response is! List) {
      throw const FormatException('Некорректный список подарков пользователя');
    }
    return response
        .whereType<Map>()
        .map((gift) => Map<String, dynamic>.from(gift))
        .toList();
  }

  static Future<void> revokeGift(String inventoryId) async {
    await _supabase.rpc(
      'revoke_gift_admin',
      params: {'p_inventory_id': inventoryId},
    );
  }

  static Future<List<Map<String, dynamic>>> getAdminGiftHistory() async {
    final response = await _supabase.rpc(
      'get_admin_gift_history',
      params: {'p_limit': 500},
    );
    if (response is! List) {
      throw const FormatException('Некорректная история подарков');
    }
    return response
        .whereType<Map>()
        .map((event) => Map<String, dynamic>.from(event))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getReceivedGifts(
    String userId,
  ) async {
    final response = await _supabase.rpc(
      'get_user_received_gifts',
      params: {'p_user_id': userId},
    );
    if (response is! List) {
      throw const FormatException('Некорректный список подарков пользователя');
    }
    return response
        .whereType<Map>()
        .map((gift) => Map<String, dynamic>.from(gift))
        .toList();
  }

  static Future<Map<String, dynamic>> upgradeGiftToNft(
    String inventoryId,
  ) async {
    final response = await _supabase.rpc(
      'upgrade_gift_to_nft',
      params: {'p_inventory_id': inventoryId},
    );
    if (response is! Map) {
      throw const FormatException('Некорректный ответ при улучшении подарка');
    }
    return Map<String, dynamic>.from(response);
  }

  static Future<Map<String, dynamic>> setGiftPinned({
    required String inventoryId,
    required bool isPinned,
  }) async {
    final response = await _supabase.rpc(
      'set_user_gift_pinned',
      params: {
        'p_inventory_id': inventoryId,
        'p_is_pinned': isPinned,
      },
    );
    if (response is! Map) {
      throw const FormatException('Некорректный ответ при закреплении подарка');
    }
    return Map<String, dynamic>.from(response);
  }

  static Future<Map<String, dynamic>> getGiftDetailsForMessage(
    String messageId,
  ) async {
    final response = await _supabase.rpc(
      'get_gift_details',
      params: {'p_message_id': messageId},
    );
    if (response is! Map) {
      throw const FormatException('Некорректные данные подарка');
    }
    return Map<String, dynamic>.from(response);
  }

  static Future<Map<String, dynamic>> getGiftDetailsBySlug(String slug) async {
    final cached = _nftDetailsCache[slug];
    if (cached != null) return cached;

    final request = _supabase
        .rpc('get_gift_details_by_slug', params: {'p_slug': slug})
        .then((response) {
          if (response is! Map) {
            throw const FormatException('Подарок по ссылке не найден');
          }
          return Map<String, dynamic>.from(response);
        });
    _nftDetailsCache[slug] = request;
    try {
      return await request;
    } catch (_) {
      if (identical(_nftDetailsCache[slug], request)) {
        _nftDetailsCache.remove(slug);
      }
      rethrow;
    }
  }
}
