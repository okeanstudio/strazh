import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:strazh/features/chat/data/services/webrtc_service.dart';

class AudioCallScreen extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String remoteUserId;
  final String contactName;
  final String? callId;
  final bool isVideo;
  final bool isIncoming;
  final String? avatarUrl;
  final String serverUrl;

  const AudioCallScreen({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.remoteUserId,
    required this.contactName,
    this.callId,
    this.isVideo = false,
    this.isIncoming = false,
    this.avatarUrl,
    required this.serverUrl,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  final WebRTCService _webrtc = WebRTCService();
  String _status = 'Подключение...';
  int _durationSeconds = 0;
  bool _muted = false;
  bool _speakerOn = false;
  bool _isConnected = false;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      await _webrtc.startCall(
        roomId: widget.chatId,
        currentUserId: widget.currentUserId,
        remoteUserId: widget.remoteUserId,
        isVideo: widget.isVideo,
        isIncoming: widget.isIncoming,
        serverUrl: widget.serverUrl,
        onStatusChange: (status) {
          if (mounted) {
            setState(() {
              _status = status;
              if (status == 'Подключено' || status == 'Соединение установлено') {
                _isConnected = true;
              }
            });
          }
        },
        onDurationUpdate: (seconds) {
          if (mounted) {
            setState(() {
              _durationSeconds = seconds;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Ошибка: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка звонка: $e')),
        );
      }
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _webrtc.toggleMute();
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _webrtc.toggleSpeaker(_speakerOn);
  }

  Future<void> _acceptCall() async {
    setState(() => _isAccepting = true);
    try {
      await _webrtc.acceptCall();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAccepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось принять звонок: $error')),
      );
    }
  }

  Future<void> _declineCall() async {
    await _webrtc.declineCall();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _hangUp() async {
    await _webrtc.hangUp();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final time = _formatDuration(_durationSeconds);
    final canAccept = widget.isIncoming && !_isConnected && !_isAccepting;
    
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Stack(
          children: [
            // Фон
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 74,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: widget.avatarUrl != null 
                        ? NetworkImage(widget.avatarUrl!) 
                        : null,
                    child: widget.avatarUrl == null 
                        ? Text(
                            widget.contactName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 52,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.contactName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected ? time : _status,
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Видео (если есть)
            if (widget.isVideo) ...[
              Positioned.fill(
                child: RTCVideoView(
                  _webrtc.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                width: 110,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RTCVideoView(
                    _webrtc.localRenderer,
                    mirror: true,
                  ),
                ),
              ),
            ],

            // Кнопки управления
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _buildControlButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    onTap: _toggleMute,
                  ),
                  
                  // Speaker
                  _buildControlButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                    onTap: _toggleSpeaker,
                  ),

                  // Ответить (только для входящего)
                  if (canAccept)
                    _buildControlButton(
                      icon: Icons.call,
                      onTap: _acceptCall,
                      color: Colors.green,
                    ),

                  // Отклонить/Завершить
                  _buildControlButton(
                    icon: canAccept
                        ? Icons.call_end 
                        : Icons.call_end,
                    onTap: canAccept
                        ? _declineCall 
                        : _hangUp,
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return IconButton(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: color ?? Colors.white12,
        foregroundColor: Colors.white,
        fixedSize: const Size(60, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      icon: Icon(icon, size: 28),
    );
  }
}