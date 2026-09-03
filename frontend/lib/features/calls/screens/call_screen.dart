import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/webrtc_call_service.dart';

const _navyDeep = Color(0xFF0B0726);

/// In-app Audio/Video call screen for a confirmed consultation. Works for
/// both the caller (the lawyer, who initiates) and the callee (the client,
/// who lands here after accepting on IncomingCallScreen) — same widget,
/// driven by [isCaller].
class CallScreen extends StatefulWidget {
  final String consultationId;
  final String peerName;
  final bool video;
  final bool isCaller;
  const CallScreen({
    super.key,
    required this.consultationId,
    required this.peerName,
    required this.video,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final WebRTCCallSession _session;
  Timer? _durationTicker;

  @override
  void initState() {
    super.initState();
    _session = WebRTCCallSession(
        consultationId: widget.consultationId, video: widget.video);
    _session.addListener(_onSessionChange);
    _session.start(isCaller: widget.isCaller);
    // Ticks the UI once a second so the live call-duration label advances —
    // the session tracks elapsed time itself; this just repaints it.
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _session.state == CallState.connected) setState(() {});
    });
  }

  void _onSessionChange() {
    if (!mounted) return;
    if (_session.state == CallState.ended ||
        _session.state == CallState.failed) {
      // Give the "call ended" state a beat to render before popping, and
      // don't try to pop an already-unmounted route.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    setState(() {});
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _durationTicker?.cancel();
    // If the peer never joined (still ringing on IncomingCallScreen, with no
    // WebRTC socket open yet), the WS hangup below has nowhere to go — this
    // is the only channel back to them, same push pipeline every other call
    // notification already uses.
    if (_session.state != CallState.connected) {
      unawaited(() async {
        try {
          await DioClient.instance
              .post('/consultations/${widget.consultationId}/call/cancel');
        } catch (_) {}
      }());
    }
    _session.removeListener(_onSessionChange);
    _session.hangup();
    _session.dispose();
    super.dispose();
  }

  String _statusLabel() {
    switch (_session.state) {
      case CallState.connecting:
        return 'Connecting…';
      case CallState.ringing:
        return widget.isCaller ? 'Calling ${widget.peerName}…' : 'Connecting…';
      case CallState.connected:
        return _formatDuration(_session.elapsedSeconds);
      case CallState.ended:
        return 'Call ended';
      case CallState.failed:
        return _session.error ?? 'Call failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _session.state == CallState.connected;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _session.hangup();
      },
      child: Scaffold(
        backgroundColor: _navyDeep,
        body: SafeArea(
          child: Stack(children: [
            // Remote video fills the screen for video calls once connected.
            if (widget.video && connected)
              Positioned.fill(
                child: RTCVideoView(_session.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              )
            else
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        widget.peerName.isNotEmpty
                            ? widget.peerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(widget.peerName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(_statusLabel(),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14)),
                ]),
              ),

            // Local self-view (video calls only)
            if (widget.video &&
                _session.localStream != null &&
                !_session.isCameraOff)
              Positioned(
                right: 16,
                top: 16,
                child: Container(
                  width: 100,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(_session.localRenderer, mirror: true),
                ),
              ),

            // Top status bar (audio calls / not-yet-connected video)
            if (!(widget.video && connected))
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(widget.video ? 'Video Call' : 'Audio Call',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                ),
              ),

            // Connected status chip for video overlay
            if (widget.video && connected)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${widget.peerName} • ${_statusLabel()}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),

            // Controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallBtn(
                    icon: _session.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    color: Colors.white.withValues(alpha: 0.18),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _session.toggleMute();
                    },
                  ),
                  const SizedBox(width: 20),
                  _CallBtn(
                    icon: _session.isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    color: _session.isSpeakerOn
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.18),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _session.toggleSpeaker();
                    },
                  ),
                  const SizedBox(width: 20),
                  _CallBtn(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFD9534F),
                    large: true,
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      context.pop();
                    },
                  ),
                  if (widget.video) ...[
                    const SizedBox(width: 20),
                    _CallBtn(
                      icon: _session.isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      color: Colors.white.withValues(alpha: 0.18),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _session.toggleCamera();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool large;
  const _CallBtn(
      {required this.icon,
      required this.color,
      required this.onTap,
      this.large = false});
  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 54.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: large ? 30 : 24),
      ),
    );
  }
}
