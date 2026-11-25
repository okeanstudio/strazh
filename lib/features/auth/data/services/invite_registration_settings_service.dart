import 'package:supabase_flutter/supabase_flutter.dart';

class InviteRegistrationSettingsService {
  InviteRegistrationSettingsService._();

  static final InviteRegistrationSettingsService instance =
      InviteRegistrationSettingsService._();

  Future<bool> isInviteCodeRequired() async {
    final result = await Supabase.instance.client.rpc(
      'get_invite_code_requirement',
    );
    if (result is! bool) {
      throw const FormatException('Некорректный статус регистрации');
    }
    return result;
  }

  Future<void> setInviteCodeRequired(bool required) async {
    await Supabase.instance.client.rpc(
      'set_invite_code_requirement',
      params: {'p_required': required},
    );
  }
}
