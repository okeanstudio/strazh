import 'package:flutter/material.dart';

class BottomNavBar extends StatefulWidget {
  static const _indicatorDuration = Duration(milliseconds: 280);
  final String currentScreen;
  final VoidCallback? onShake;
  final bool isDesktop;
  final Function(String)? onNavigate;

  const BottomNavBar({
    super.key,
    required this.currentScreen,
    this.onShake,
    this.isDesktop = false,
    this.onNavigate,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  late int _currentIndex;
  bool _transitioning = false;

  static int _screenIndex(String screenName) {
    switch (screenName) {
      case 'settings':
        return 0;
      case 'home':
        return 1;
      case 'profile':
        return 2;
      default:
        return 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _screenIndex(widget.currentScreen);
  }

  @override
  void didUpdateWidget(covariant BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentScreen != widget.currentScreen) {
      _currentIndex = _screenIndex(widget.currentScreen);
    }
  }

  Future<void> _navigateTo(String screenName, int targetIndex) async {
    if (_transitioning) return;
    if (targetIndex == _currentIndex) {
      widget.onShake?.call();
      return;
    }

    setState(() {
      _currentIndex = targetIndex;
      _transitioning = true;
    });

    await Future.delayed(BottomNavBar._indicatorDuration);
    if (!mounted) return;

    if (widget.onNavigate != null) {
      widget.onNavigate!(screenName);
    }
    setState(() => _transitioning = false);
  }

  @override
  Widget build(BuildContext context) {
    // ================= ДЕСКТОП: ВЕРТИКАЛЬНЫЙ ЧИСТЫЙ СТОЛБИк =================
    if (widget.isDesktop) {
      return Container(
        padding: const EdgeInsets.only(
          top: 16,
          bottom: 24,
          left: 12,
          right: 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF151323),
          border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDesktopIcon(Icons.settings, 'settings', 0),
            const SizedBox(width: 24),
            _buildDesktopIcon(Icons.chat_sharp, 'home', 1),
            const SizedBox(width: 24),
            _buildDesktopIcon(Icons.person, 'profile', 2),
          ],
        ),
      );
    }

    // ================= МОБИЛЬНЫЙ: ГОРИЗОНТАЛЬНЫЙ БЕГУНОК =================
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const accentColor = Color(0xFF7442F5);
          const sidePadding = 12.0;
          const indicatorSize = 52.0;
          final buttonWidth = (constraints.maxWidth - sidePadding * 2) / 3;
          final indicatorLeft =
              sidePadding +
              _currentIndex * buttonWidth +
              (buttonWidth - indicatorSize) / 2;

          return SizedBox(
            height: 64,
            child: Stack(
              children: [
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF111020), Color(0xFF1B182D)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: BottomNavBar._indicatorDuration,
                  curve: Curves.easeOutCubic,
                  left: indicatorLeft,
                  top: 6,
                  width: indicatorSize,
                  height: indicatorSize,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor,
                          accentColor.withValues(alpha: 0.86),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.4,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: sidePadding),
                  child: Row(
                    children: [
                      SizedBox(
                        width: buttonWidth,
                        child: _buildIcon(
                          context,
                          Icons.settings,
                          'settings',
                          0,
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: _buildIcon(context, Icons.chat_sharp, 'home', 1),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: _buildIcon(context, Icons.person, 'profile', 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon(
    BuildContext context,
    IconData icon,
    String screenName,
    int index,
  ) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _navigateTo(screenName, index),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        scale: isActive ? 1.08 : 1,
        child: Center(
          child: Icon(icon, color: Colors.white, size: isActive ? 30 : 28),
        ),
      ),
    );
  }

  Widget _buildDesktopIcon(IconData icon, String screenName, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _navigateTo(screenName, index),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF7442F5) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF7442F5).withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Icon(
            icon,
            color: isActive ? Colors.white : Colors.grey[400],
            size: 26,
          ),
        ),
      ),
    );
  }
}
