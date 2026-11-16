import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/features/settings/data/services/wallpaper_service.dart';
import 'package:strazh/features/settings/presentation/screens/wallpaper_screen.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen>
    with WidgetsBindingObserver {
  late String _selectedTheme;
  late String _selectedAccent;
  late String _selectedFontFamily;
  late bool _fontItalic;
  late String _selectedWallpaper;
  late String _selectedIcon;
  bool _hasSubscription = false;

  final List<String> _themes = ['Тёмная', 'Светлая', 'Системная'];

  static const List<Map<String, String>> _fontOptions = [
    {'name': 'Системный', 'family': '', 'sample': 'Привет, Strazh'},
    {
      'name': 'Округлый',
      'family': 'sans-serif-rounded',
      'sample': 'Мягкие формы',
    },
    {'name': 'Книжный', 'family': 'serif', 'sample': 'Читать приятнее'},
    {'name': 'Моноширинный', 'family': 'monospace', 'sample': 'CODE 123'},
    {'name': 'Рукописный', 'family': 'cursive', 'sample': 'Своя атмосфера'},
    {'name': 'Пиксельный', 'family': 'PixelifySans', 'sample': 'МИР БЛОКОВ'},
  ];

  static const String _iconPrefsKey = 'app_icon_variant';

  static const List<Map<String, String>> _appIcons = [
    {
      'id': 'default',
      'name': 'Классическая',
      'asset': 'assets/icon/icon.png',
      'iosName': 'default',
    },
    {
      'id': 'icon1',
      'name': 'Старый Strazh',
      'asset': 'assets/icon/icon1.png',
      'iosName': 'icon1',
    },
    {
      'id': 'icon2',
      'name': 'Strazh Infinity',
      'asset': 'assets/icon/icon2.png',
      'iosName': 'icon2',
    },
  ];

  final List<AccentThemeData> _accentThemes = [
    const AccentThemeData(
      name: 'Красно-оранжевый',
      myBubble: Color(0xFFE85D3A),
      otherBubble: Color(0xFF2A1A14),
      myText: Colors.white,
      otherText: Color(0xFFFFC8B8),
    ),
    const AccentThemeData(
      name: 'Изумрудный',
      myBubble: Color(0xFF2D9B6E),
      otherBubble: Color(0xFF142A1E),
      myText: Colors.white,
      otherText: Color(0xFF88CCA8),
    ),
    const AccentThemeData(
      name: 'Океанский синий',
      myBubble: Color(0xFF2B7DB8),
      otherBubble: Color(0xFF142A3E),
      myText: Colors.white,
      otherText: Color(0xFF88B8D8),
    ),
    const AccentThemeData(
      name: 'Золотистый янтарь',
      myBubble: Color(0xFFD4A02B),
      otherBubble: Color(0xFF2A2214),
      myText: Colors.white,
      otherText: Color(0xFFD4C088),
    ),
    const AccentThemeData(
      name: 'Розовый закат',
      myBubble: Color(0xFFD45A8A),
      otherBubble: Color(0xFF2A1422),
      myText: Colors.white,
      otherText: Color(0xFFD488B0),
    ),
    const AccentThemeData(
      name: 'Лавандовый',
      myBubble: Color(0xFF8B7AC8),
      otherBubble: Color(0xFF1E1A2E),
      myText: Colors.white,
      otherText: Color(0xFFB8A8D8),
    ),
    const AccentThemeData(
      name: 'Мятный',
      myBubble: Color(0xFF3AA68A),
      otherBubble: Color(0xFF142A22),
      myText: Colors.white,
      otherText: Color(0xFF88D4BE),
    ),
    const AccentThemeData(
      name: 'Терракотовый',
      myBubble: Color(0xFFC47A4A),
      otherBubble: Color(0xFF2A1E14),
      myText: Colors.white,
      otherText: Color(0xFFD4B098),
    ),
    const AccentThemeData(
      name: 'Фиолетовый',
      myBubble: Color(0xFF7442F5),
      otherBubble: Color(0xFF211735),
      myText: Colors.white,
      otherText: Color(0xFFD1C2EF),
    ),
    const AccentThemeData(
      name: 'Небесно-голубой',
      myBubble: Color(0xFF4A9BD9),
      otherBubble: Color(0xFF142A3E),
      myText: Colors.white,
      otherText: Color(0xFF88C8E8),
    ),
    const AccentThemeData(
      name: 'Коралловый',
      myBubble: Color(0xFFE87060),
      otherBubble: Color(0xFF2A1A14),
      myText: Colors.white,
      otherText: Color(0xFFFFC8B8),
    ),
    const AccentThemeData(
      name: 'Лаймовый',
      myBubble: Color(0xFF6BBF4A),
      otherBubble: Color(0xFF142A1A),
      myText: Colors.white,
      otherText: Color(0xFFA8D888),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedTheme = ThemeService().themeMode.value;
    _selectedAccent = ThemeService().currentTheme.value.name;
    _selectedFontFamily = ThemeService().fontFamily.value;
    _fontItalic = ThemeService().fontItalic.value;
    _selectedWallpaper = WallpaperService.defaultWallpaper;
    _selectedIcon = 'default';
    _loadWallpaper();
    _loadIcon();
    _loadSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSubscription();
    }
  }

  AccentThemeData get _currentAccent {
    return _accentThemes.firstWhere(
      (t) => t.name == _selectedAccent,
      orElse: () => _accentThemes[0],
    );
  }

  Future<void> _loadWallpaper() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final wp = await WallpaperService.getWallpaper(userId);
    if (mounted) setState(() => _selectedWallpaper = wp);
  }

  Future<void> _loadIcon() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_iconPrefsKey) ?? 'default';
    if (mounted) setState(() => _selectedIcon = id);
  }

  Future<void> _loadSubscription() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.auth.refreshSession();

      final freshUser = Supabase.instance.client.auth.currentUser;
      final meta = freshUser?.userMetadata ?? user.userMetadata ?? {};
      final active = meta['subscription_active'] == true;
      final expiresRaw = meta['subscription_expires_at'];

      bool valid = false;
      if (active && expiresRaw != null) {
        if (expiresRaw.toString() == 'forever') {
          valid = true;
        } else {
          final d = DateTime.tryParse(expiresRaw.toString());
          valid = d != null && d.isAfter(DateTime.now());
        }
      }

      if (mounted) setState(() => _hasSubscription = valid);
    } catch (e) {
      debugPrint('Ошибка загрузки подписки: $e');
    }
  }

  bool _isIconLocked(String iconId) {
    return iconId == 'icon2' && !_hasSubscription;
  }

  Future<void> _saveIcon(Map<String, String> icon) async {
    final id = icon['id']!;

    if (_isIconLocked(id)) {
      Toast.warning(
        context,
        '🔒 Иконка «Strazh Infinity» доступна только с подпиской',
      );
      return;
    }

    try {
      final supported = await FlutterDynamicIconPlus.supportsAlternateIcons;
      if (!supported) {
        if (mounted) Toast.info(context, 'Смена иконки не поддерживается');
        return;
      }

      final androidIconName = switch (id) {
        'default' => 'default',
        'icon1' => '1',
        'icon2' => '2',
        _ => null,
      };
      final iconName = defaultTargetPlatform == TargetPlatform.android
          ? 'com.okeanstudio.strazh.launcher_icon_$androidIconName'
          : (id == 'default' ? null : icon['iosName']);

      await FlutterDynamicIconPlus.setAlternateIconName(
        iconName: iconName,
        isSilent: true,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_iconPrefsKey, id);

      if (mounted) {
        setState(() => _selectedIcon = id);
        Toast.success(
          context,
          defaultTargetPlatform == TargetPlatform.android
              ? 'Иконка применится после закрытия приложения'
              : 'Иконка обновлена',
        );
      }
    } catch (e) {
      debugPrint('Ошибка смены иконки: $e');
      if (mounted) Toast.error(context, 'Не удалось сменить иконку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _currentAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Темы и оформление',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () async {
              final selected = _accentThemes.firstWhere(
                (t) => t.name == _selectedAccent,
                orElse: () => _accentThemes[0],
              );

              ThemeService().setTheme(selected);
              ThemeService().setThemeMode(_selectedTheme);
              ThemeService().fontFamily.value = _selectedFontFamily;
              ThemeService().fontItalic.value = _fontItalic;
              await ThemeService().saveTheme();
              if (!context.mounted) return;

              Toast.success(context, 'Тема сохранена: $_selectedAccent');
              Navigator.pop(context, true);
            },
            child: const Text(
              'Сохранить',
              style: TextStyle(
                color: Color(0xFF7C6F9E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Режим оформления'),
            const SizedBox(height: 8),
            _buildThemeModeSelector(),

            const SizedBox(height: 24),

            _buildSectionHeader('Шрифт приложения'),
            const SizedBox(height: 8),
            _buildFontSelector(),
            const SizedBox(height: 8),
            _buildItalicToggle(),

            const SizedBox(height: 24),

            _buildSectionHeader('Акцентный цвет'),
            const SizedBox(height: 8),
            _buildAccentScrollList(),

            const SizedBox(height: 24),

            _buildSectionHeader('Обои чата'),
            const SizedBox(height: 8),
            _buildWallpaperSection(),

            const SizedBox(height: 24),

            _buildSectionHeader('Предпросмотр'),
            const SizedBox(height: 8),
            _buildPreviewCard(accent),

            const SizedBox(height: 24),

            _buildSectionHeader('Иконка приложения'),
            const SizedBox(height: 8),
            _buildIconSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[500],
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildIconSection() {
    return Row(
      children: _appIcons.map((icon) {
        final id = icon['id']!;
        final isSelected = id == _selectedIcon;
        final isLocked = _isIconLocked(id);

        return Expanded(
          child: GestureDetector(
            onTap: () => _saveIcon(icon),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF15121C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.05),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Opacity(
                        opacity: isLocked ? 0.35 : 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            icon['asset']!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFF282828),
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isLocked)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock,
                                color: Colors.amber,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    icon['name']!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isLocked
                          ? Colors.grey[600]
                          : (isSelected ? Colors.white : Colors.grey[500]),
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (isLocked)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Infinity',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFontSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _fontOptions.map((option) {
            final family = option['family']!;
            final isSelected = family == _selectedFontFamily;
            return GestureDetector(
              onTap: () => setState(() => _selectedFontFamily = family),
              child: Container(
                width: cardWidth,
                constraints: const BoxConstraints(minHeight: 86),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6C5B8F).withValues(alpha: 0.18)
                      : const Color(0xFF15121C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF9A84C9)
                        : Colors.white.withValues(alpha: 0.06),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option['name']!,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFFB9A6E5),
                            size: 17,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      option['sample']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family.isEmpty ? null : family,
                        fontStyle: _fontItalic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildItalicToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15121C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: SwitchListTile.adaptive(
        value: _fontItalic,
        onChanged: (value) => setState(() => _fontItalic = value),
        activeTrackColor: const Color(0xFF9A84C9),
        title: const Text(
          'Курсив',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Наклонное начертание для всего приложения',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        secondary: const Icon(Icons.format_italic, color: Color(0xFFB9A6E5)),
      ),
    );
  }

  Widget _buildThemeModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15121C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: _themes.map((theme) {
          final isSelected = theme == _selectedTheme;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTheme = theme),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6C5B8F).withValues(alpha: 0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      theme == 'Тёмная'
                          ? Icons.nightlight_round
                          : theme == 'Светлая'
                          ? Icons.light_mode
                          : Icons.settings_suggest,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey[500],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      theme,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[500],
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccentScrollList() {
    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: _accentThemes.map((theme) {
            final isSelected = theme.name == _selectedAccent;
            return GestureDetector(
              onTap: () => setState(() => _selectedAccent = theme.name),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.myBubble.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? theme.myBubble
                        : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.myBubble,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: theme.otherBubble,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      theme.name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[400],
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWallpaperSection() {
    return GestureDetector(
      onTap: _openWallpaperPicker,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF15121C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _buildWallpaperMiniPreview(_selectedWallpaper),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Текущие обои',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _wallpaperName(_selectedWallpaper),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 20),
          ],
        ),
      ),
    );
  }

  String _wallpaperName(String value) {
    if (value.startsWith('http')) return 'Свои обои';
    return WallpaperService.getPreset(value).name;
  }

  Widget _buildWallpaperMiniPreview(String wallpaper) {
    if (wallpaper.startsWith('http')) {
      return CustomPaint(painter: _WallpaperMiniPreview(wallpaper));
    }

    final imageAsset = WallpaperService.getPreset(wallpaper).imageAsset;
    if (imageAsset != null) {
      return Image.asset(imageAsset, fit: BoxFit.cover);
    }

    return CustomPaint(painter: _WallpaperMiniPreview(wallpaper));
  }

  Future<void> _openWallpaperPicker() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => WallpaperScreen(
          userId: userId,
          currentWallpaper: _selectedWallpaper,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedWallpaper = result);
    }
  }

  Widget _buildPreviewCard(AccentThemeData accent) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: WallpaperBackground(
          wallpaper: _selectedWallpaper,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: const Color(0xFF0D0A0A).withValues(alpha: 0.85),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      child: Text(
                        'S',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Strazh Messenger',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'онлайн',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(Icons.call, color: Colors.grey[600], size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.videocam,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800]!.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Сегодня',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          child: Text(
                            'U',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: const BoxConstraints(maxWidth: 180),
                          decoration: BoxDecoration(
                            color: accent.otherBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.04),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Привет! Как дела?',
                                style: TextStyle(
                                  color: accent.otherText,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '14:30',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: const BoxConstraints(maxWidth: 180),
                          decoration: BoxDecoration(
                            color: accent.myBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Отлично! А у тебя?',
                                style: TextStyle(
                                  color: accent.myText,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '14:32',
                                style: TextStyle(
                                  color: accent.myText.withValues(alpha: 0.6),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          child: Text(
                            'Y',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          child: Text(
                            'U',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: const BoxConstraints(maxWidth: 180),
                          decoration: BoxDecoration(
                            color: accent.otherBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.04),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Тоже хорошо :)',
                                style: TextStyle(
                                  color: accent.otherText,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '14:33',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withValues(alpha: 0.85),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.attach_file,
                        color: Colors.grey[600],
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF282828),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          'Сообщение...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.emoji_emotions,
                        color: Colors.grey[600],
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.myBubble,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WallpaperMiniPreview extends CustomPainter {
  final String wallpaper;
  _WallpaperMiniPreview(this.wallpaper);

  @override
  void paint(Canvas canvas, Size size) {
    if (wallpaper.startsWith('http')) {
      final paint = Paint()..color = const Color(0xFF1F1F1F);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      final icon = Icons.image;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 22,
            fontFamily: icon.fontFamily,
            color: Colors.white70,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }

    final preset = WallpaperService.getPreset(wallpaper);
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: preset.colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      gradientPaint,
    );

    if (preset.pattern == WallpaperPattern.icons) {
      const icons = <IconData>[
        Icons.lock_outline,
        Icons.shield_outlined,
        Icons.vpn_key_outlined,
        Icons.mail_outline,
        Icons.fingerprint,
        Icons.security_outlined,
      ];
      const cell = 18.0;
      const iconSize = 7.0;
      final random = _SeededRandom(42);
      for (double y = 0; y < size.height; y += cell) {
        for (double x = 0; x < size.width; x += cell) {
          final icon = icons[random.nextInt(icons.length)];
          final tp = TextPainter(
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontSize: iconSize,
                fontFamily: icon.fontFamily,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x, y));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperMiniPreview old) =>
      old.wallpaper != wallpaper;
}

class _SeededRandom {
  int _state;
  _SeededRandom(int seed) : _state = seed;
  double nextDouble() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }

  int nextInt(int max) => (nextDouble() * max).floor();
}
