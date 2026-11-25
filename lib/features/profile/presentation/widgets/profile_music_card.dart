import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class ProfileMusicCard extends StatefulWidget {
  final String url;
  final String title;

  const ProfileMusicCard({super.key, required this.url, required this.title});

  @override
  State<ProfileMusicCard> createState() => _ProfileMusicCardState();
}

class _ProfileMusicCardState extends State<ProfileMusicCard> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _isPlaying = false;
  bool _hasStarted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Object? _playbackError;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      }),
      _player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.onDurationChanged.listen((duration) {
        if (mounted && duration > Duration.zero) {
          setState(() => _duration = duration);
        }
      }),
      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
          _hasStarted = false;
        });
      }),
    ]);
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else if (_hasStarted) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
        _hasStarted = true;
      }
      if (mounted) setState(() => _playbackError = null);
    } catch (error) {
      if (mounted) setState(() => _playbackError = error);
    }
  }

  Future<void> _seek(Duration position) async {
    if (!_hasStarted || _duration <= Duration.zero) return;
    try {
      await _player.seek(position);
    } catch (error) {
      if (mounted) setState(() => _playbackError = error);
    }
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMilliseconds = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final positionMilliseconds = _position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF353535)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF78A9FF),
              fixedSize: const Size(42, 42),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 9,
                    ),
                    activeTrackColor: const Color(0xFF78A9FF),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: const Color(0xFF78A9FF),
                    overlayColor: const Color(
                      0xFF78A9FF,
                    ).withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMilliseconds,
                    value: positionMilliseconds,
                    onChanged: !_hasStarted || _duration <= Duration.zero
                        ? null
                        : (value) {
                            final target = Duration(
                              milliseconds: value.round(),
                            );
                            setState(() => _position = target);
                            _seek(target);
                          },
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _format(_position),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _format(_duration),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
                if (_playbackError != null)
                  const Text(
                    'Не удалось воспроизвести трек',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
