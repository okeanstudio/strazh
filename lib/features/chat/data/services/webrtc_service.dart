import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  
  socket_io.Socket? _socket;
  
  String? _currentCallId;
  String? _currentUserId;
  String? _remoteUserId;
  String? _roomId;
  
  Function(String status)? _onStatusChange;
  Function(int duration)? _onDurationUpdate;
  Function(Map<String, dynamic> callData)? _onIncomingCall;
  
  bool _isIncoming = false;
  Timer? _durationTimer;
  int _durationSeconds = 0;
  bool _isInitialized = false;
  bool _isWaitingForAnswer = false;

  bool get isConnected => _peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  bool get isCallActive => _currentCallId != null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _isInitialized = true;
      debugPrint('✅ WebRTCService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing renderers: $e');
      rethrow;
    }
  }

  Future<void> connectToServer({
    required String serverUrl,
    required String userId,
    required String roomId,
    Function(Map<String, dynamic>)? onIncomingCall,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    _currentUserId = userId;
    _roomId = roomId;
    _onIncomingCall = onIncomingCall;

    _socket = socket_io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
    });

    final completer = Completer<void>();

    _socket!.on('connect', (_) {
      debugPrint('✅ Connected to signaling server');
      _socket!.emit('join', {
        'room': _roomId,
        'userId': _currentUserId,
      });
      if (!completer.isCompleted) completer.complete();
    });

    _socket!.on('joined', (data) {
      debugPrint('📨 Joined room: ${data['room']}');
    });

    _socket!.on('users', (data) {
      debugPrint('👥 Users updated: $data');
    });

    _socket!.on('signal', (data) {
      final from = data['from'] as String;
      final signal = data['signal'] as Map<String, dynamic>;
      final type = signal['type'] as String;
      
      if (from == _currentUserId) return;

      debugPrint('📨 Signal from $from: $type');

      if (type == 'offer') {
        _remoteUserId = from;
        _isIncoming = true;
        _currentCallId = '${from}_${DateTime.now().millisecondsSinceEpoch}';
        
        if (_onIncomingCall != null) {
          _onIncomingCall!({
            'from': from,
            'callId': _currentCallId,
            'isVideo': signal['isVideo'] ?? false,
          });
        }
        _pendingOffer = signal;
        return;
      }

      if (_currentCallId == null) return;
      _handleSignal(from, signal);
    });

    _socket!.on('connect_error', (error) {
      debugPrint('❌ Connection error: $error');
      if (!completer.isCompleted) completer.completeError(error);
    });

    _socket!.on('disconnect', (_) {
      debugPrint('❌ Disconnected from signaling server');
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('Connection timeout'),
    );
  }

  Map<String, dynamic>? _pendingOffer;
  bool _isAnswering = false;

  void _handleSignal(String from, Map<String, dynamic> signal) async {
    final peer = _peerConnection;
    if (peer == null) return;

    try {
      final type = signal['type'] as String;
      
      switch (type) {
        case 'offer':
          if (_isIncoming) {
            await peer.setRemoteDescription(
              RTCSessionDescription(signal['sdp'], signal['type'])
            );
            final answer = await peer.createAnswer();
            await peer.setLocalDescription(answer);
            _sendSignal('answer', {
              'sdp': answer.sdp,
              'type': answer.type,
            });
          }
          break;

        case 'answer':
          if (!_isIncoming) {
            await peer.setRemoteDescription(
              RTCSessionDescription(signal['sdp'], signal['type'])
            );
            _setStatus('Соединение установлено');
            _startDurationTimer();
          }
          break;

        case 'candidate':
          await peer.addCandidate(
            RTCIceCandidate(
              signal['candidate'],
              signal['sdpMid'],
              signal['sdpMLineIndex'],
            )
          );
          break;

        case 'hangup':
          _setStatus('Звонок завершен');
          await _cleanup();
          break;

        case 'decline':
          _setStatus('Звонок отклонен');
          await _cleanup();
          break;

        default:
          break;
      }
    } catch (e) {
      _setStatus('Ошибка сигнала: $e');
    }
  }

  Future<void> startCall({
    required String roomId,
    required String currentUserId,
    required String remoteUserId,
    required bool isVideo,
    required bool isIncoming,
    required String serverUrl,
    Function(String status)? onStatusChange,
    Function(int duration)? onDurationUpdate,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    _roomId = roomId;
    _currentUserId = currentUserId;
    _remoteUserId = remoteUserId;
    _isIncoming = isIncoming;
    _onStatusChange = onStatusChange;
    _onDurationUpdate = onDurationUpdate;
    _durationSeconds = 0;
    _currentCallId ??= '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}';

    if (isIncoming) {
      _setStatus('Входящий звонок');
      return;
    }

    try {
      if (_socket == null || !_socket!.connected) {
        await _connectSignaling(serverUrl);
      }

      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
        ],
      });

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          _sendSignal('candidate', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty && _isInitialized) {
          remoteRenderer.srcObject = event.streams.first;
          _setStatus('Подключено');
          _startDurationTimer();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _setStatus('Соединение установлено');
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _setStatus('Соединение потеряно');
            break;
          default:
            break;
        }
      };

      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      if (_isInitialized) {
        localRenderer.srcObject = _localStream;
      }

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      if (!_isIncoming) {
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _sendSignal('offer', {
          'sdp': offer.sdp,
          'type': offer.type,
          'isVideo': isVideo,
        });
        _setStatus('Ожидание ответа...');
        _isWaitingForAnswer = true;
      } else {
        _setStatus('Входящий звонок...');
        _isWaitingForAnswer = false;
      }
    } catch (e) {
      _setStatus('Ошибка: $e');
      rethrow;
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_pendingOffer == null || _isAnswering) return;
    _isAnswering = true;

    try {
      if (_peerConnection == null) {
        _peerConnection = await createPeerConnection({
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun2.l.google.com:19302'},
          ],
        });

        _peerConnection!.onIceCandidate = (candidate) {
          if (candidate.candidate != null) {
            _sendSignal('candidate', {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            });
          }
        };

        _peerConnection!.onTrack = (event) {
          if (event.streams.isNotEmpty && _isInitialized) {
            remoteRenderer.srcObject = event.streams.first;
            _setStatus('Подключено');
            _startDurationTimer();
          }
        };

        final mediaConstraints = <String, dynamic>{
          'audio': true,
          'video': _pendingOffer!['isVideo'] == true ? {'facingMode': 'user'} : false,
        };
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        
        if (_isInitialized) {
          localRenderer.srcObject = _localStream;
        }

        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(_pendingOffer!['sdp'], _pendingOffer!['type'])
      );
      
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      
      _sendSignal('answer', {
        'sdp': answer.sdp,
        'type': answer.type,
      });

      _pendingOffer = null;
      _isIncoming = false;
      _isAnswering = false;
      _setStatus('Соединение устанавливается...');
      
    } catch (e) {
      debugPrint('❌ Error accepting call: $e');
      _isAnswering = false;
      _setStatus('Ошибка: $e');
      rethrow;
    }
  }

  Future<void> declineIncomingCall() async {
    if (_pendingOffer != null) {
      _sendSignal('decline', {});
      _pendingOffer = null;
      _isIncoming = false;
      await _cleanup();
    }
  }

  Future<void> _connectSignaling(String serverUrl) async {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('join', {
        'room': _roomId,
        'userId': _currentUserId,
      });
      return;
    }

    _socket = socket_io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
    });

    final completer = Completer<void>();

    _socket!.on('connect', (_) {
      debugPrint('✅ Connected to signaling server');
      _socket!.emit('join', {
        'room': _roomId,
        'userId': _currentUserId,
      });
      if (!completer.isCompleted) completer.complete();
    });

    _socket!.on('joined', (data) {
      debugPrint('📨 Joined room: ${data['room']}');
    });

    _socket!.on('users', (data) {
      debugPrint('👥 Users updated: $data');
    });

    _socket!.on('signal', (data) {
      final from = data['from'] as String;
      final signal = data['signal'] as Map<String, dynamic>;
      if (from != _currentUserId) {
        _handleSignal(from, signal);
      }
    });

    _socket!.on('connect_error', (error) {
      debugPrint('❌ Connection error: $error');
      if (!completer.isCompleted) completer.completeError(error);
    });

    _socket!.on('disconnect', (_) {
      debugPrint('❌ Disconnected from signaling server');
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('Connection timeout'),
    );
  }

  void _sendSignal(String type, Map<String, dynamic> data) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ Socket not connected');
      return;
    }
    
    _socket!.emit('signal', {
      'to': _remoteUserId,
      'from': _currentUserId,
      'signal': {
        'type': type,
        ...data,
      },
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      _onDurationUpdate?.call(_durationSeconds);
    });
  }

  void _setStatus(String status) {
    _onStatusChange?.call(status);
  }

  void toggleMute() {
    final audioTracks = _localStream?.getAudioTracks();
    if (audioTracks != null && audioTracks.isNotEmpty) {
      final enabled = !audioTracks.first.enabled;
      for (final track in audioTracks) {
        track.enabled = enabled;
      }
    }
  }

  void toggleSpeaker(bool enable) {}

  Future<void> acceptCall() async {
    await acceptIncomingCall();
  }

  Future<void> declineCall() async {
    _sendSignal('decline', {});
    await _cleanup();
  }

  Future<void> hangUp() async {
    _sendSignal('hangup', {});
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _durationSeconds = 0;
    _currentCallId = null;
    _pendingOffer = null;
    _isIncoming = false;
    _isWaitingForAnswer = false;
    _isAnswering = false;
    _remoteUserId = null;
    
    if (_localStream != null) {
      _localStream!.dispose();
      _localStream = null;
    }
    
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
    
    // НЕ ТРОГАЕМ РЕНДЕРЕРЫ здесь!
    // Они очищаются только в dispose()
  }

  void disconnectFromServer() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _cleanup();
  }

  void dispose() {
    _durationTimer?.cancel();
    _cleanup();
    if (_isInitialized) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isInitialized = false;
  }
}