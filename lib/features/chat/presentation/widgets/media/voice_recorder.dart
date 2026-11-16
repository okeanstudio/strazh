import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class VoiceRecorder extends StatefulWidget {
  final void Function(File audioFile) onSend;
  final Future<void> Function()? onStartVideoNote;
  final Future<void> Function()? onStopVideoNote;
  final bool isVideoNoteActive;

  const VoiceRecorder({
    super.key,
    required this.onSend,
    this.onStartVideoNote,
    this.onStopVideoNote,
    this.isVideoNoteActive = false,
  });

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVideoNoteMode = false;
  bool _isVideoNoteLocked = false;
  bool _isHoldingVideoNote = false;
  int _audioRecordingSession = 0;

  @override
  void didUpdateWidget(covariant VoiceRecorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVideoNoteActive && !widget.isVideoNoteActive) {
      _isVideoNoteLocked = false;
      _isHoldingVideoNote = false;
    }
  }

  Future<void> _startRecording() async {
    final session = ++_audioRecordingSession;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!mounted || session != _audioRecordingSession) return;
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет разрешения на запись микрофона')),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      if (!mounted || session != _audioRecordingSession) return;
      final filePath =
          '${tempDir.path}/voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: filePath,
      );

      if (!mounted || session != _audioRecordingSession) {
        final stoppedPath = await _recorder.stop();
        if (stoppedPath != null) {
          final file = File(stoppedPath);
          if (await file.exists()) await file.delete();
        }
        return;
      }
      setState(() => _isRecording = true);
    } catch (e) {
      if (mounted && session == _audioRecordingSession) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка записи: $e')));
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      if (mounted) {
        setState(() => _isRecording = false);
      }

      if (path != null && File(path).existsSync()) {
        widget.onSend(File(path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка остановки записи: $e')));
      }
    }
  }

  void _startFromPress() {
    if (_isVideoNoteMode) {
      setState(() {
        _isVideoNoteLocked = false;
        _isHoldingVideoNote = true;
      });
      final startVideoNote = widget.onStartVideoNote;
      if (startVideoNote != null) unawaited(startVideoNote());
    } else {
      unawaited(_startRecording());
    }
  }

  void _moveWhilePressing(LongPressMoveUpdateDetails details) {
    if (_isVideoNoteMode &&
        _isHoldingVideoNote &&
        !_isVideoNoteLocked &&
        details.offsetFromOrigin.dy < -72) {
      setState(() => _isVideoNoteLocked = true);
    }
  }

  void _endPress() {
    if (_isVideoNoteMode) {
      if (!_isVideoNoteLocked && _isHoldingVideoNote) {
        final stopVideoNote = widget.onStopVideoNote;
        if (stopVideoNote != null) unawaited(stopVideoNote());
      }
      setState(() => _isHoldingVideoNote = false);
    } else {
      _audioRecordingSession++;
      if (_isRecording) unawaited(_stopRecording());
    }
  }

  void _cancelPress() {
    if (_isVideoNoteMode) {
      if (_isHoldingVideoNote && !_isVideoNoteLocked) {
        final stopVideoNote = widget.onStopVideoNote;
        if (stopVideoNote != null) unawaited(stopVideoNote());
      }
      setState(() => _isHoldingVideoNote = false);
    } else {
      _audioRecordingSession++;
      if (_isRecording) unawaited(_stopRecording());
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isRecording || widget.isVideoNoteActive) return;
        setState(() => _isVideoNoteMode = !_isVideoNoteMode);
      },
      onLongPressStart: (_) => _startFromPress(),
      onLongPressMoveUpdate: _moveWhilePressing,
      onLongPressEnd: (_) => _endPress(),
      onLongPressCancel: _cancelPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _isRecording || _isHoldingVideoNote
              ? Colors.red
              : const Color(0xFF211735).withValues(alpha: 0.95),
          shape: BoxShape.circle,
          border: Border.all(
            color: _isRecording || _isHoldingVideoNote
                ? Colors.red
                : const Color(0xFF9B5CFF).withValues(alpha: 0.24),
            width: 1,
          ),
        ),
        child: Icon(
          _isVideoNoteLocked
              ? Icons.lock
              : _isVideoNoteMode
              ? Icons.videocam_rounded
              : _isRecording
              ? Icons.mic
              : Icons.mic_none,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
