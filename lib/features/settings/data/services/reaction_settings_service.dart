import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/core/config/reactions.dart';

class ReactionSettingsService {
  static Future<String> getDoubleTapReaction() async {
    final preferences = await SharedPreferences.getInstance();
    final savedReaction = preferences.getString(doubleTapReactionPreferenceKey);
    if (savedReaction != null &&
        availableReactionEmojis.contains(savedReaction)) {
      return savedReaction;
    }
    return defaultDoubleTapReaction;
  }

  static Future<void> setDoubleTapReaction(String reaction) async {
    if (!availableReactionEmojis.contains(reaction)) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(doubleTapReactionPreferenceKey, reaction);
  }
}
