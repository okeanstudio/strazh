import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:strazh/features/gifts/data/services/gift_animation_cache.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';

String giftAnimationAssetPath({required String name, String? giftId}) {
  const knownGiftIds = {
    'rose',
    'heart',
    'cake',
    'teddy',
    'diamond',
    'crown',
    'lolipop',
    'poop',
    'casino',
  };
  const idsByName = {
    'роза': 'rose',
    'rose': 'rose',
    'сердце': 'heart',
    'heart': 'heart',
    'торт': 'cake',
    'cake': 'cake',
    'мишка': 'teddy',
    'teddy': 'teddy',
    'бриллиант': 'diamond',
    'diamond': 'diamond',
    'корона': 'crown',
    'crown': 'crown',
    'леденец': 'lolipop',
    'lolipop': 'lolipop',
    'какашка': 'poop',
    'poop': 'poop',
    'казино': 'casino',
    'casino': 'casino',
  };

  final id = giftId?.trim().toLowerCase();
  final key = id != null && knownGiftIds.contains(id)
      ? id
      : idsByName[name.trim().toLowerCase()] ?? 'gift_box';
  return 'assets/gifts/$key.json';
}

class GiftAnimation extends StatefulWidget {
  const GiftAnimation({
    super.key,
    required this.name,
    this.giftId,
    this.animationUrl,
    this.size = 240,
    this.playDuration,
  });

  final String name;
  final String? giftId;
  final String? animationUrl;
  final double size;
  final Duration? playDuration;

  @override
  State<GiftAnimation> createState() => _GiftAnimationState();
}

class _GiftAnimationState extends State<GiftAnimation>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _stopTimer;
  bool _hasStartedLimitedPlayback = false;
  Future<String?>? _animationUrlFuture;
  Future<Uint8List?>? _animationBytesFuture;
  String? _animationBytesUrl;

  @override
  void initState() {
    super.initState();
    if (widget.playDuration != null) {
      _controller = AnimationController(vsync: this);
    }
    _prepareAnimationRequests();
  }

  @override
  void didUpdateWidget(covariant GiftAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name == widget.name &&
        oldWidget.giftId == widget.giftId &&
        oldWidget.animationUrl == widget.animationUrl &&
        oldWidget.playDuration == widget.playDuration) {
      return;
    }
    _stopTimer?.cancel();
    _controller?.dispose();
    _hasStartedLimitedPlayback = false;
    _controller = widget.playDuration == null
        ? null
        : AnimationController(vsync: this);
    _prepareAnimationRequests();
  }

  void _prepareAnimationRequests() {
    final explicitUrl = widget.animationUrl?.trim();
    final asset = giftAnimationAssetPath(
      name: widget.name,
      giftId: widget.giftId,
    );
    _animationUrlFuture =
        explicitUrl != null && explicitUrl.isNotEmpty
        ? null
        : widget.giftId?.trim().isNotEmpty == true ||
              asset == 'assets/gifts/gift_box.json'
        ? GiftService.getAnimationUrl(
            name: widget.name,
            giftId: widget.giftId,
          )
        : null;
    _animationBytesFuture = null;
    _animationBytesUrl = null;
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startLimitedPlayback(LottieComposition composition) {
    final controller = _controller;
    final duration = widget.playDuration;
    if (controller == null ||
        duration == null ||
        _hasStartedLimitedPlayback) {
      return;
    }
    _hasStartedLimitedPlayback = true;
    controller.duration = composition.duration;
    controller.forward(from: 0);
    _stopTimer?.cancel();
    _stopTimer = Timer(duration, controller.stop);
  }

  @override
  Widget build(BuildContext context) {
    final asset = giftAnimationAssetPath(
      name: widget.name,
      giftId: widget.giftId,
    );
    final explicitUrl = widget.animationUrl?.trim();
    if (explicitUrl != null && explicitUrl.isNotEmpty) {
      return _remoteAnimation(explicitUrl, asset);
    }
    if (_animationUrlFuture != null) {
      return FutureBuilder<String?>(
        future: _animationUrlFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint(
              'Не удалось получить ссылку на анимацию подарка: ${snapshot.error}',
            );
          }
          final url = snapshot.data;
          if (url == null || url.isEmpty) return _localAnimation(asset);
          return _remoteAnimation(url, asset);
        },
      );
    }
    return _localAnimation(asset);
  }

  Widget _remoteAnimation(String url, String fallbackAsset) {
    if (_animationBytesUrl != url) {
      _animationBytesUrl = url;
      _animationBytesFuture = GiftAnimationCache.load(
        giftId: widget.giftId ?? widget.name,
        url: url,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _animationBytesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'Не удалось загрузить анимацию подарка: ${snapshot.error}',
          );
          return _localAnimation(fallbackAsset);
        }
        final bytes = snapshot.data;
        if (bytes == null) return _localAnimation(fallbackAsset);
        return Lottie.memory(
          bytes,
          controller: _controller,
          repeat: widget.playDuration == null,
          onLoaded: widget.playDuration == null
              ? null
              : _startLimitedPlayback,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Не удалось отобразить анимацию подарка: $error');
            return _localAnimation(fallbackAsset);
          },
        );
      },
    );
  }

  Widget _localAnimation(String asset) {
    return Lottie.asset(
      asset,
      controller: _controller,
      repeat: widget.playDuration == null,
      onLoaded: widget.playDuration == null ? null : _startLimitedPlayback,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Не удалось отобразить локальную анимацию подарка: $error');
        if (asset == 'assets/gifts/gift_box.json') {
          return Icon(
            Icons.card_giftcard_rounded,
            size: widget.size * 0.55,
            color: const Color(0xFFFFC86B),
          );
        }
        return Lottie.asset(
          'assets/gifts/gift_box.json',
          controller: _controller,
          repeat: widget.playDuration == null,
          onLoaded: widget.playDuration == null ? null : _startLimitedPlayback,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.card_giftcard_rounded,
            size: widget.size * 0.55,
            color: const Color(0xFFFFC86B),
          ),
        );
      },
    );
  }
}

class AnimatedGiftCard extends StatelessWidget {
  const AnimatedGiftCard({
    super.key,
    required this.name,
    this.giftId,
    this.animationUrl,
    this.caption = '',
    this.senderName,
    this.compact = false,
  });

  final String name;
  final String? giftId;
  final String? animationUrl;
  final String caption;
  final String? senderName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final compact = this.compact;
    final animationSize = compact ? 92.0 : 240.0;
    return SizedBox(
      width: animationSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: animationSize,
            height: animationSize,
            child: GiftAnimation(
              name: name,
              giftId: giftId,
              animationUrl: animationUrl,
              size: animationSize,
            ),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 13 : 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '«$caption»',
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFFFE7C0),
                fontSize: compact ? 11 : 14,
                height: 1.25,
              ),
            ),
          ],
          if (senderName?.isNotEmpty == true) ...[
            SizedBox(height: compact ? 4 : 7),
            Text(
              'от $senderName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white54,
                fontSize: compact ? 10 : 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
