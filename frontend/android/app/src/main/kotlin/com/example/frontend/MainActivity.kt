package com.libra.law

import android.content.ContentValues
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.libra.law/upi"
    private val RINGTONE_CHANNEL = "com.libra.law/ringtone"
    private val DOWNLOADS_CHANNEL = "com.libra.law/downloads"
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

        // Smart Draft's Word/PDF export used to only hand the file to the OS
        // share sheet (Save to Files / send to another app) — nothing was
        // actually saved unless the user picked that option there, which
        // read as "nothing downloaded". This saves the file straight into
        // the device's real Downloads folder, the same place a browser
        // download lands, using MediaStore so no storage permission is
        // needed on Android 10+ (this app's practical minimum).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName == null || mimeType == null || bytes == null) {
                    result.error("INVALID_ARGS", "fileName/mimeType/bytes required", null)
                } else {
                    try {
                        result.success(saveToDownloads(fileName, mimeType, bytes))
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(fileName: String, mimeType: String, bytes: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return false
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return false
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return true
        }
        // Pre-Android 10: no MediaStore.Downloads collection, and this app
        // does not declare WRITE_EXTERNAL_STORAGE — fall back to the
        // existing share-sheet flow on the Dart side for these older
        // devices instead of requesting a new runtime permission for them.
        val publicDownloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!publicDownloads.canWrite()) return false
        FileOutputStream(File(publicDownloads, fileName)).use { it.write(bytes) }
        return true
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