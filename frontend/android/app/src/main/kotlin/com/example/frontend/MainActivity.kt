package com.libra.law

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.libra.law/upi"
    private val RINGTONE_CHANNEL = "com.libra.law/ringtone"
    private var ringtonePlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchUrl") {
                val url = call.argument<String>("url")
                if (url != null) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LAUNCH_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_URL", "URL is null", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Loops the device's own default ringtone for an incoming call, using
        // the phone's actual ringtone/volume routing rather than a bundled
        // sound file — no audio asset to ship, and it sounds like the phone
        // ringing rather than a generic notification blip. Implemented
        // directly rather than via a plugin: the one third-party package for
        // this (flutter_ringtone_player) ships an AAR compiled against
        // android-33, which fails AGP's metadata check against this
        // project's compileSdk 36 and can't build at all.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    playRingtone()
                    result.success(null)
                }
                "stop" -> {
                    stopRingtone()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playRingtone() {
        stopRingtone()
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: return
            ringtonePlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@MainActivity, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            // No ringtone accessible on this device — the call still
            // connects, it just won't audibly ring.
        }
    }

    private fun stopRingtone() {
        ringtonePlayer?.let {
            try {
                if (it.isPlaying) it.stop()
            } catch (e: Exception) {
                // Already stopped/released — nothing to do.
            }
            it.release()
        }
        ringtonePlayer = null
    }

    override fun onDestroy() {
        stopRingtone()
        super.onDestroy()
    }
}