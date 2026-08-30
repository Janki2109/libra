import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/fcm_service.dart';

/// Shown when a push notification tells the client their lawyer is calling
/// for a confirmed Audio/Video consultation (see FcmService's onMessage /
/// onMessageOpenedApp handlers). On accept this hands off into the in-app
/// WebRTC CallScreen (same session the lawyer is already connecting to) —
/// it only gives the client a clear place to accept or decline first, and
/// rings/vibrates the device in the meantime.
class IncomingCallScreen extends StatefulWidget {
  final String consultationId;
  final String callType; // 'audio' | 'video'
  final String lawyerName;
  const IncomingCallScreen({
    super.key,
    required this.consultationId,
    required this.callType,
    required this.lawyerName,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _ringTimer;
  bool _responding = false;
  bool _endedByCaller = false;

  @override
  void initState() {
    super.initState();
    // No ringtone-asset/audio-player dependency exists in this project yet,
    // so the device is made to actually ring using capabilities Flutter
    // already ships with: a repeating haptic buzz plus the platform alert
    // sound, rather than adding a new package for one screen.
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
    FcmService.instance.callCancelled.addListener(_onCallCancelled);
  }

  void _onCallCancelled() {
    if (FcmService.instance.callCancelled.value != widget.consultationId) {
      return;
    }
    // The caller hung up before this screen answered — stop ringing and
    // dismiss, same as if the callee had declined, but without posting a
    // response back (there is nothing left to respond to).
    if (!mounted || _responding) return;
    setState(() {
      _responding = true;
      _endedByCaller = true;
    });
    _ringTimer?.cancel();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    FcmService.instance.callCancelled.removeListener(_onCallCancelled);
    super.dispose();
  }

  Future<void> _respond(String response) async {
    if (_responding) return;
    setState(() => _responding = true);
    _ringTimer?.cancel();
    try {
      await DioClient.instance.post(
          '/portal/my-consultations/${widget.consultationId}/call-response',
          data: {'response': response});
    } catch (_) {
      // The lawyer just won't get the "declined/accepted" push — the call
      // itself (dialer/meeting link) below does not depend on this.
    }

    if (response == 'declined') {
      if (mounted) context.pop();
      return;
    }

    // Accepted — join the same in-app WebRTC session the lawyer is already
    // connecting to for this consultation.
    if (mounted) {
      context.pop();
      context.push('/call', extra: {
        'consultationId': widget.consultationId,
        'peerName': widget.lawyerName,
        'video': widget.callType == 'video',
        'isCaller': false,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A2E1F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(children: [
              const Spacer(),
              Text(
                  _endedByCaller
                      ? 'Call Ended'
                      : (isVideo ? 'Incoming Video Call' : 'Incoming Audio Call'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 28),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Center(
                    child: Text(
                        widget.lawyerName.isNotEmpty
                            ? widget.lawyerName[0].toUpperCase()
                            : 'L',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 20),
              Text(widget.lawyerName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(isVideo ? 'Video Consultation' : 'Audio Consultation',
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFD9534F),
                    label: 'Decline',
                    onTap: _responding ? null : () => _respond('declined'),
                  ),
                  _CallActionButton(
                    icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFF2E8B57),
                    label: 'Accept',
                    onTap: _responding ? null : () => _respond('accepted'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  const _CallActionButton(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]);
}
