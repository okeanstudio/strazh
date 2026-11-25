import 'package:flutter/material.dart';

class ChatMessageLoading extends StatefulWidget {
  const ChatMessageLoading({super.key});

  @override
  State<ChatMessageLoading> createState() => _ChatMessageLoadingState();
}

class _ChatMessageLoadingState extends State<ChatMessageLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  static const _bubbleWidths = [
    184.0,
    132.0,
    226.0,
    158.0,
    198.0,
    118.0,
    176.0,
  ];
  static const _bubbleHeights = [46.0, 38.0, 58.0, 42.0, 50.0, 38.0, 46.0];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final color = Color.lerp(
          const Color(0xFF211735),
          const Color(0xFF382554),
          _shimmerController.value,
        )!;
        return ListView.builder(
          reverse: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          itemCount: _bubbleWidths.length,
          itemBuilder: (context, index) {
            final isMine = index.isOdd;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
              child: Row(
                mainAxisAlignment: isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMine) ...[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    width: _bubbleWidths[index],
                    height: _bubbleHeights[index],
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 5),
                        bottomRight: Radius.circular(isMine ? 5 : 18),
                      ),
                    ),
                  ),
                  if (isMine) const SizedBox(width: 38),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class ChatMessageEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final bool animate;

  const ChatMessageEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.animate = true,
  });

  @override
  State<ChatMessageEntrance> createState() => _ChatMessageEntranceState();
}

class _ChatMessageEntranceState extends State<ChatMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curve);

    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
