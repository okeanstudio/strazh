import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileNftDecorationService {
  ProfileNftDecorationService._();

  static final _supabase = Supabase.instance.client;

  static Future<Map<String, Map<int, String>>> getForUser(String userId) async {
    final rows = await _supabase
        .from('user_profile_nft_decorations')
        .select('placement, slot, gift_inventory_id')
        .eq('user_id', userId);

    final decorations = <String, Map<int, String>>{'avatar': {}, 'name': {}};
    for (final row in rows) {
      final placement = row['placement'] as String;
      final slot = row['slot'] as int;
      final inventoryId = row['gift_inventory_id'] as String;
      decorations[placement]![slot] = inventoryId;
    }
    return decorations;
  }

  static Future<void> setDecoration({
    required String placement,
    required int slot,
    required String? inventoryId,
  }) async {
    await _supabase.rpc(
      'set_user_profile_nft_decoration',
      params: {
        'p_placement': placement,
        'p_slot': slot,
        'p_inventory_id': inventoryId,
      },
    );
  }
}
