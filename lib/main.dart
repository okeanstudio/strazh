import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/core/services/app_language_service.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:strazh/features/chat/data/services/notification_service.dart';
import 'package:flutter_desktop_notifications/flutter_desktop_notifications.dart';
import 'package:window_manager/window_manager.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/app/presentation/screens/update_required_screen.dart';
import 'package:strazh/features/chat/data/services/fcm_service.dart';
import 'package:strazh/core/services/supabase_initializer.dart';
import 'package:strazh/core/config/firebase_web_config.dart';
import 'package:strazh/core/config/firebase_options.dart';
import 'package:strazh/features/settings/data/services/sound_service.dart';
import 'package:strazh/features/auth/data/services/account_session_service.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===== FIREBASE =====
  var firebaseInitialized = false;
  try {
    final options = kIsWeb
        ? await FirebaseWebConfig.load()
        : DefaultFirebaseOptions.currentPlatform;
    if (options != null) {
      await Firebase.initializeApp(options: options);
      firebaseInitialized = true;
      debugPrint('✅ Firebase инициализирован');
    }
  } catch (e) {
    debugPrint('❌ Ошибка Firebase: $e');
  }

  // ===== WINDOW MANAGER (desktop) =====
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1200, 800),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      debugPrint('✅ WindowManager инициализирован');
    } catch (e) {
      debugPrint('⚠️ WindowManager ошибка: $e');
    }
  }

  // ===== SYSTEM UI =====
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0D0A0A),
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarColor: Color(0xFF0D0A0A),
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // ===== AUMID (Windows) =====
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      debugPrint('Регистрация AUMID...');
      await WindowsNotification.registerAumid(
        aumid: 'com.denotestudio.strazh',
        displayName: 'Strazh',
      );
      debugPrint('AUMID зарегистрирован');
    } catch (e) {
      debugPrint('⚠️ Ошибка регистрации AUMID: $e');
    }
  }

  // ===== УВЕДОМЛЕНИЯ =====
  if (!kIsWeb) {
    try {
      debugPrint('Инициализация уведомлений...');
      if (firebaseInitialized ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux) {
        await NotificationService().initialize();
        debugPrint('Уведомления инициализированы');
      } else {
        debugPrint('Уведомления пропущены: Firebase не инициализирован');
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка инициализации уведомлений: $e');
    }
  }

  // ===== SUPABASE =====
  try {
    debugPrint('Инициализация Supabase...');
    await SupabaseInitializer.initialize();
    await AccountSessionService().initialize();
    debugPrint('✅ Supabase инициализирован');
  } catch (e) {
    debugPrint('❌ Ошибка Supabase: $e');
  }

  // ===== НАСТРОЙКИ ЗВУКОВ И УВЕДОМЛЕНИЙ =====
  try {
    await SoundService().loadSettings();
  } catch (e) {
    debugPrint('⚠️ Ошибка загрузки настроек звуков: $e');
  }

  // ===== FCM =====
  try {
    if (firebaseInitialized) {
      await FcmService().initialize();
      debugPrint('✅ FCM инициализирован');
    } else if (!kIsWeb) {
      debugPrint('FCM пропущен: Firebase не инициализирован');
    } else {
      debugPrint('ℹ️ Firebase Web Push не настроен');
    }
  } catch (e) {
    debugPrint('❌ Ошибка FCM: $e');
  }

  // ===== ТЕМА =====
  try {
    debugPrint('Загрузка темы...');
    await ThemeService().loadTheme();
    debugPrint('Тема загружена: ${ThemeService().currentTheme.value.name}');
  } catch (e) {
    debugPrint('⚠️ Ошибка загрузки темы: $e');
  }

  try {
    await AppLanguageService().load();
  } catch (e) {
    debugPrint('⚠️ Ошибка загрузки языка: $e');
  }

  debugPrint('Запуск приложения...');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
    _setUserOnlineIfNeeded();
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      final online = _isOnline(result);
      debugPrint('🌐 Стартовая проверка: $result → online=$online');
      setState(() => _hasInternet = online);

      _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
        if (!mounted) return;
        final online = _isOnline(results);
        debugPrint('🌐 Смена сети: $results → online=$online');
        if (online != _hasInternet) {
          setState(() => _hasInternet = online);
        }
      });
    } catch (e) {
      debugPrint('⚠️ Ошибка проверки сети: $e');
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn ||
          r == ConnectivityResult.other,
    );
  }

  /// Вызывается из NoInternetScreen по кнопке "Проверить снова".
  Future<bool> _recheckInternet() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final online = _isOnline(results);
      debugPrint('🌐 Перепроверка по кнопке: $results → online=$online');
      if (!mounted) return online;
      if (online != _hasInternet) {
        setState(() => _hasInternet = online);
      }
      return online;
    } catch (e) {
      debugPrint('⚠️ Ошибка перепроверки: $e');
      return false;
    }
  }

  Future<void> _setUserOnlineIfNeeded() async {
    try {
      if (await _authService.isLoggedIn()) {
        await _authService.setUserOnline();
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка установки статуса: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (state == AppLifecycleState.resumed) {
        _authService.setUserOnline();
        _recheckInternet();
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.detached) {
        _authService.setUserOffline();
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка жизненного цикла: $e');
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ThemeService().currentTheme,
      builder: (context, theme, child) {
        return ValueListenableBuilder(
          valueListenable: ThemeService().fontFamily,
          builder: (context, fontFamily, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: ThemeService().fontItalic,
              builder: (context, fontItalic, child) {
                return ValueListenableBuilder(
                  valueListenable: ThemeService().themeMode,
                  builder: (context, mode, child) {
                    final isDark =
                        mode == 'Тёмная' ||
                        (mode == 'Системная' &&
                            MediaQuery.of(context).platformBrightness ==
                                Brightness.dark);

                    return ValueListenableBuilder<Locale>(
                      valueListenable: AppLanguageService().locale,
                      builder: (context, locale, child) => MaterialApp(
                        title: 'Strazh',
                        debugShowCheckedModeBanner: false,
                        theme: isDark
                            ? _buildDarkTheme(theme, fontFamily, fontItalic)
                            : _buildLightTheme(theme, fontFamily, fontItalic),
                        localizationsDelegates: const [
                          GlobalMaterialLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalCupertinoLocalizations.delegate,
                        ],
                        supportedLocales: const [
                          Locale('ru'),
                          Locale('en'),
                          Locale('kk'),
                        ],
                        locale: locale,
                        home: _hasInternet
                            ? (!kIsWeb
                                  ? const UpdateReminderScreen(
                                      upToDateScreen: SplashScreen(),
                                    )
                                  : const SplashScreen())
                            : NoInternetScreen(onRetry: _recheckInternet),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  ThemeData _buildDarkTheme(
    AccentThemeData theme,
    String fontFamily,
    bool fontItalic,
  ) {
    return ThemeData(
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      textTheme: _appTextTheme(Brightness.dark, fontFamily, fontItalic),
      primaryTextTheme: _appTextTheme(Brightness.dark, fontFamily, fontItalic),
      brightness: Brightness.dark,
      primaryColor: theme.myBubble,
      scaffoldBackgroundColor: const Color(0xFF0D0A0A),
      colorScheme: ColorScheme.dark(
        primary: theme.myBubble,
        secondary: theme.myBubble,
        surface: const Color(0xFF0D0A0A),
        onSurface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D0A0A),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF181516),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF181516),
        modalBackgroundColor: Color(0xFF181516),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF201D1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.myBubble,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.myBubble;
          }
          return Colors.grey[400];
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.myBubble.withValues(alpha: 0.35);
          }
          return Colors.grey.withValues(alpha: 0.2);
        }),
      ),
    );
  }

  ThemeData _buildLightTheme(
    AccentThemeData theme,
    String fontFamily,
    bool fontItalic,
  ) {
    return ThemeData(
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      textTheme: _appTextTheme(Brightness.light, fontFamily, fontItalic),
      primaryTextTheme: _appTextTheme(Brightness.light, fontFamily, fontItalic),
      brightness: Brightness.light,
      primaryColor: theme.myBubble,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      colorScheme: ColorScheme.light(
        primary: theme.myBubble,
        secondary: theme.myBubble,
        surface: Colors.white,
        onSurface: Colors.black87,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black87),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.myBubble,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.myBubble;
          }
          return Colors.grey[400];
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.myBubble.withValues(alpha: 0.35);
          }
          return Colors.grey.withValues(alpha: 0.2);
        }),
      ),
    );
  }

  TextTheme _appTextTheme(
    Brightness brightness,
    String fontFamily,
    bool fontItalic,
  ) {
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final base = brightness == Brightness.dark
        ? typography.white
        : typography.black;
    final styled = base.apply(
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
    );
    TextStyle? style(TextStyle? value) => value?.copyWith(
      fontStyle: fontItalic ? FontStyle.italic : FontStyle.normal,
    );

    return styled.copyWith(
      displayLarge: style(styled.displayLarge),
      displayMedium: style(styled.displayMedium),
      displaySmall: style(styled.displaySmall),
      headlineLarge: style(styled.headlineLarge),
      headlineMedium: style(styled.headlineMedium),
      headlineSmall: style(styled.headlineSmall),
      titleLarge: style(styled.titleLarge),
      titleMedium: style(styled.titleMedium),
      titleSmall: style(styled.titleSmall),
      bodyLarge: style(styled.bodyLarge),
      bodyMedium: style(styled.bodyMedium),
      bodySmall: style(styled.bodySmall),
      labelLarge: style(styled.labelLarge),
      labelMedium: style(styled.labelMedium),
      labelSmall: style(styled.labelSmall),
    );
  }
}

// ================= ЭКРАН "НЕТ ИНТЕРНЕТА" =================

class NoInternetScreen extends StatefulWidget {
  final Future<bool> Function() onRetry;

  const NoInternetScreen({super.key, required this.onRetry});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  bool _isChecking = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _errorText = null;
    });

    final ok = await widget.onRetry();
    if (!mounted) return;

    setState(() {
      _isChecking = false;
      if (!ok) _errorText = 'Интернет всё ещё недоступен';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulse.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF6C5CE7,
                            ).withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF4A9EFF,
                            ).withValues(alpha: 0.18),
                            blurRadius: 70,
                            spreadRadius: 16,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              const Text(
                'Нет интернета',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Проверьте подключение к сети\nи попробуйте снова',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],

              const SizedBox(height: 40),

              SizedBox(
                width: 220,
                child: TextButton(
                  onPressed: _isChecking ? null : _handleRetry,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(
                      0xFF6C5CE7,
                    ).withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isChecking)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFFB8A8FF),
                          size: 20,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isChecking ? 'Проверяем...' : 'Проверить снова',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= SPLASH =================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Color(0xFF0D0A0A),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Color(0xFF0D0A0A),
          statusBarIconBrightness: Brightness.light,
        ),
      );
    });

    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    try {
      final isLoggedIn = await _authService.isLoggedIn();
      if (!mounted) return;

      final user = _authService.getCurrentUser();
      final metadata = user?.userMetadata;
      final tag = metadata?['tag'] as String?;

      if (isLoggedIn && tag != null) {
        if (user != null) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          await _authService.logout();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
        }
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthScreen()),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка проверки авторизации: $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [StrazhSLoader(size: 112, label: 'STRAZH')],
        ),
      ),
    );
  }
}
