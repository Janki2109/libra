import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/app_constants.dart';
import 'dio_client.dart';
import 'storage_service.dart';

enum CallState { connecting, ringing, connected, ended, failed }

/// Free, self-hosted in-app calling for a confirmed Audio/Video consultation
/// booking. Media goes peer-to-peer over WebRTC using free public STUN
/// servers, falling back to a TURN relay when one is configured (see
/// AppConstants.hasTurnServer) for the calls STUN alone can't connect across
/// a restrictive NAT — no Twilio/Agora. The backend's
/// `/consultations/:id/call/ws` endpoint only relays the
/// offer/answer/ICE-candidate handshake, never the media itself.
///
/// One instance is created per call attempt and owned by the screen that
/// starts it — not a singleton, since a user is never in more than one call.
class WebRTCCallSession extends ChangeNotifier {
  final String consultationId;
  final bool video;
  CallState state = CallState.connecting;

  RTCPeerConnection? _pc;
  MediaStream? localStream;
  MediaStream? remoteStream;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  bool _isCaller = false;
  bool _madeOffer = false;
  bool _closed = false;
  String? _error;
  DateTime? _connectedAt;
  bool isSpeakerOn = false;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  WebRTCCallSession({required this.consultationId, required this.video});

  String? get error => _error;

  bool get isMuted =>
      localStream?.getAudioTracks().any((t) => !t.enabled) ?? false;

  bool get isCameraOff =>
      video && (localStream?.getVideoTracks().any((t) => !t.enabled) ?? false);

  Future<void> start({required bool isCaller}) async {
    _isCaller = isCaller;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();

      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user'} : false,
      });
      localRenderer.srcObject = localStream;

      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          // STUN alone can't connect a call across a symmetric/carrier-grade
          // NAT (common on Indian mobile data) — a TURN server relays media
          // in that case instead. Omitted entirely (rather than sent empty)
          // when none is configured, since some platforms reject an
          // ice-server entry with a blank username/credential. Four
          // variants of the same relay (plain UDP, TCP-on-80, UDP-on-443,
          // TLS-on-443) rather than one: a network that blocks plain UDP
          // outright often still lets 443 traffic through, so offering all
          // of them gives ICE the best chance of finding one that works
          // instead of gambling on a single transport.
          if (AppConstants.hasTurnServer) ...[
            {'urls': 'stun:stun.relay.metered.ca:80'},
            {
              'urls': 'turn:global.relay.metered.ca:80',
              'username': AppConstants.turnUsername,
              'credential': AppConstants.turnCredential,
            },
            {
              'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
              'username': AppConstants.turnUsername,
              'credential': AppConstants.turnCredential,
            },
            {
              'urls': 'turn:global.relay.metered.ca:443',
              'username': AppConstants.turnUsername,
              'credential': AppConstants.turnCredential,
            },
            {
              'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
              'username': AppConstants.turnUsername,
              'credential': AppConstants.turnCredential,
            },
          ],
        ],
      });

      for (final track in localStream!.getTracks()) {
        await _pc!.addTrack(track, localStream!);
      }

      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          remoteRenderer.srcObject = remoteStream;
          state = CallState.connected;
          _connectedAt ??= DateTime.now();
          // Video calls default to the earpiece speaker like a normal call
          // otherwise, so switch to the loud speaker automatically once
          // connected — matches how every other calling app behaves.
          if (video) {
            isSpeakerOn = true;
            Helper.setSpeakerphoneOn(true);
          }
          notifyListeners();
        }
      };

      _pc!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;
        _send({
          'type': 'ice-candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      _pc!.onConnectionState = (RTCPeerConnectionState s) {
        if (_closed) return;
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          state = CallState.failed;
          notifyListeners();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          state = CallState.ended;
          notifyListeners();
        }
      };

      await _connectSignaling();
    } catch (e) {
      _error = 'Could not access camera/microphone. Please check permissions.';
      state = CallState.failed;
      notifyListeners();
    }
  }

  Future<void> _connectSignaling() async {
    final token = await StorageService.getToken();
    // AppConstants.baseUrl is e.g. "http://host:8080/api/v1" — the signaling
    // endpoint reuses the exact same host/port, just over ws:// instead.
    final wsBase = AppConstants.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final uri =
        Uri.parse('$wsBase/consultations/$consultationId/call/ws?token=$token');
    try {
      _channel = WebSocketChannel.connect(uri);
      state = CallState.ringing;
      notifyListeners();
      _wsSub = _channel!.stream.listen(
        _onSignal,
        onDone: () {
          if (!_closed) {
            state = CallState.ended;
            notifyListeners();
          }
        },
        onError: (_) {
          if (!_closed) {
            _error = 'Connection lost. Please try again.';
            state = CallState.failed;
            notifyListeners();
          }
        },
      );
    } catch (_) {
      _error = 'Unable to connect. Please try again.';
      state = CallState.failed;
      notifyListeners();
    }
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _onSignal(dynamic raw) async {
    if (_pc == null) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['type']) {
      case 'peer-joined':
        if (_isCaller && !_madeOffer) {
          _madeOffer = true;
          final offer = await _pc!.createOffer();
          await _pc!.setLocalDescription(offer);
          _send({'type': 'offer', 'sdp': offer.sdp});
        }
        break;
      case 'offer':
        await _pc!
            .setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _send({'type': 'answer', 'sdp': answer.sdp});
        break;
      case 'answer':
        await _pc!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'));
        break;
      case 'ice-candidate':
        if (data['candidate'] != null) {
          await _pc!.addCandidate(RTCIceCandidate(
              data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
        break;
      case 'peer-left':
      case 'hangup':
        if (!_closed) {
          state = CallState.ended;
          notifyListeners();
        }
        break;
    }
  }

  void toggleMute() {
    final tracks = localStream?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !t.enabled;
    }
    notifyListeners();
  }

  void toggleCamera() {
    final tracks = localStream?.getVideoTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !t.enabled;
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    Helper.setSpeakerphoneOn(isSpeakerOn);
    notifyListeners();
  }

  /// Seconds spent actually connected — 0 before the peer ever joined, still
  /// counting up live once connected (the UI timer reads this every second).
  int get elapsedSeconds =>
      _connectedAt == null ? 0 : DateTime.now().difference(_connectedAt!).inSeconds;

  /// Persists the connected duration against the consultation once the call
  /// ends, so consultation history has a real number to show instead of
  /// nothing — this was never recorded anywhere before.
  Future<void> _saveDuration() async {
    if (_connectedAt == null) return;
    final seconds = DateTime.now().difference(_connectedAt!).inSeconds;
    try {
      await DioClient.instance.post(
          '/consultations/$consultationId/call/duration',
          data: {'duration_seconds': seconds});
    } catch (_) {
      // Best-effort — a failed save shouldn't block ending the call.
    }
  }

  Future<void> hangup() async {
    if (_closed) return;
    _closed = true;
    await _saveDuration();
    _send({'type': 'hangup'});
    await _wsSub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    state = CallState.ended;
    notifyListeners();
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
