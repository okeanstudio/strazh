import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final VoidCallback onClose;

  const AudioPlayerWidget({super.key, required this.url, required this.onClose});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    //debugPrint('🎵 AudioPlayerWidget инициализирован');
    //debugPrint('🎵 URL: ${widget.url}');
    _initPlayer();

    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _player.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d;
          _isLoaded = true;
        });
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
        _player.seek(Duration.zero);
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setSourceUrl(widget.url);
      if (mounted) setState(() => _isLoaded = true);
    } catch (e, stack) {
      debugPrint('❌ Ошибка загрузки аудио: $e\n$stack');
      if (mounted) {
        setState(() => _error = e.toString());
        Toast.error(context, 'Не удалось загрузить голосовое: $e');
      }
    }
  }

  void _playPause() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        Toast.error(context, 'Ошибка воспроизведения: $e');
      }
    }
  }

  String _format(Duration d) {
    if (d == Duration.zero) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    //debugPrint('🎵 AudioPlayerWidget уничтожен');
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: widget.onClose,
            ),
          ],
        ),
      );
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Кнопка Play/Pause
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFF1A73E8),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
              onPressed: _playPause,
            ),
          ),
          const SizedBox(width: 10),

          // Область слайдера и времени
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Слайдер с уменьшенной высотой
                SizedBox(
                  height: 24, // Жестко ограничиваем высоту слайдера
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds
                            .toDouble()
                            .clamp(0.0, _duration.inMilliseconds.toDouble())
                        : 0.0,
                    max: _duration.inMilliseconds.toDouble() > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (v) {
                      _player.seek(Duration(milliseconds: v.toInt()));
                    },
                    activeColor: const Color(0xFF1A73E8),
                    inactiveColor: Colors.grey.withValues(alpha: 0.3),
                    min: 0,
                  ),
                ),
                
                // Тайминги (уменьшен шрифт и отступы)
                Padding(
                  padding: const EdgeInsets.only(top: 0), // Убрали лишний отступ
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _format(_position),
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Text(
                        _isLoaded ? _format(_duration) : '0:00',
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Кнопка закрытия
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              _player.stop();
              widget.onClose();
            },
          ),
        ],
      ),
    );
  }
}