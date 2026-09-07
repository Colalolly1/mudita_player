package com.muditakompakt.mudita_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.EventChannel
import java.io.File

/**
 * Foreground service that hosts a MediaSession so the OS, car, lock screen,
 * and Bluetooth headphones know what's playing and can control it.
 *
 * Audio decoding still happens in just_audio on the Flutter side — this
 * service is a "shadow" session that mirrors that state. We don't take
 * over playback; we only tell Android about it.
 */
class MediaPlaybackService : Service() {
    companion object {
        const val CHANNEL_ID = "mudita_playback_channel"
        const val NOTIFICATION_ID = 1001
        private const val TAG = "MuditaMediaSession"

        const val ACTION_PLAY = "play"
        const val ACTION_PAUSE = "pause"
        const val ACTION_NEXT = "next"
        const val ACTION_PREVIOUS = "previous"
        const val ACTION_STOP = "stop"
        const val ACTION_SEEK = "seek"

        @Volatile
        var instance: MediaPlaybackService? = null

        @Volatile
        var eventSink: EventChannel.EventSink? = null
    }

    private lateinit var mediaSession: MediaSessionCompat

    // Multi-tap detection for single-button headsets.
    private val tapHandler = Handler(Looper.getMainLooper())
    private var tapCount = 0
    private var tapRunnable: Runnable? = null

    private var lastTitle = ""
    private var lastArtist: String? = null
    private var lastAlbum: String? = null
    private var lastDurationMs: Long = 0L
    private var lastArtPath: String? = null
    private var lastPlaying = false
    private var lastPositionMs: Long = 0L

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()

        val mediaButtonReceiver =
            android.content.ComponentName(this, MediaButtonReceiver::class.java)
        mediaSession = MediaSessionCompat(this, "MuditaPlayer", mediaButtonReceiver, null).apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    sendAction(ACTION_PLAY)
                }
                override fun onPause() {
                    sendAction(ACTION_PAUSE)
                }
                override fun onSkipToNext() {
                    sendAction(ACTION_NEXT)
                }
                override fun onSkipToPrevious() {
                    sendAction(ACTION_PREVIOUS)
                }
                override fun onStop() {
                    sendAction(ACTION_STOP)
                }
                override fun onSeekTo(pos: Long) {
                    sendAction("$ACTION_SEEK:$pos")
                }

                // Intercept raw media-button events so we can implement
                // single/double/triple-tap on single-button headsets, which
                // Android does NOT detect for us reliably.
                override fun onMediaButtonEvent(intent: Intent): Boolean {
                    val key: KeyEvent? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                Intent.EXTRA_KEY_EVENT, KeyEvent::class.java
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                        }
                    if (key == null || key.action != KeyEvent.ACTION_DOWN) {
                        return super.onMediaButtonEvent(intent)
                    }
                    return when (key.keyCode) {
                        KeyEvent.KEYCODE_MEDIA_NEXT -> {
                            sendAction(ACTION_NEXT); true
                        }
                        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                            sendAction(ACTION_PREVIOUS); true
                        }
                        KeyEvent.KEYCODE_MEDIA_PLAY -> {
                            sendAction(ACTION_PLAY); true
                        }
                        KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                            sendAction(ACTION_PAUSE); true
                        }
                        KeyEvent.KEYCODE_HEADSETHOOK,
                        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                            if (key.repeatCount == 0) registerTap()
                            true
                        }
                        else -> super.onMediaButtonEvent(intent)
                    }
                }
            })
            // These flags make us eligible to be the system's active media
            // session, which is required for volume-key routing when locked.
            @Suppress("DEPRECATION")
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            // Tell the system our volume keys control the MUSIC stream, so
            // turning the volume wheel changes media volume — not ringtone —
            // even when the screen is off or we're in the background.
            setPlaybackToLocal(AudioManager.STREAM_MUSIC)
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            MediaButtonReceiver.handleIntent(mediaSession, intent)
        } catch (t: Throwable) {
            Log.w(TAG, "media button intent failed", t)
        }
        // Re-show notification so the foreground service stays alive.
        showNotification()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun updateMetadata(
        title: String,
        artist: String?,
        album: String?,
        durationMs: Long,
        artPath: String?,
    ) {
        lastTitle = title
        lastArtist = artist
        lastAlbum = album
        lastDurationMs = durationMs
        lastArtPath = artPath

        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

        if (artPath != null) {
            try {
                val cleanPath =
                    if (artPath.startsWith("file://")) artPath.substring(7) else artPath
                val file = File(cleanPath)
                if (file.exists()) {
                    val bmp = BitmapFactory.decodeFile(cleanPath)
                    if (bmp != null) {
                        builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp)
                        builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, bmp)
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "could not load art bitmap", t)
            }
        }

        mediaSession.setMetadata(builder.build())
        showNotification()
    }

    /// Count taps within a 500ms window: 1 = play/pause, 2 = next, 3 = prev.
    private fun registerTap() {
        tapCount++
        tapRunnable?.let { tapHandler.removeCallbacks(it) }
        val r = Runnable {
            when (tapCount) {
                1 -> sendAction(if (lastPlaying) ACTION_PAUSE else ACTION_PLAY)
                2 -> sendAction(ACTION_NEXT)
                else -> sendAction(ACTION_PREVIOUS)
            }
            tapCount = 0
        }
        tapRunnable = r
        tapHandler.postDelayed(r, 500)
    }

    fun updatePlaybackState(playing: Boolean, positionMs: Long) {
        lastPlaying = playing
        lastPositionMs = positionMs
        // NOTE: We deliberately do NOT request audio focus here. just_audio
        // (via the audio_session package) already owns audio focus while
        // playing. A second focus request from this same app would revoke
        // just_audio's focus and instantly pause playback.

        val state = if (playing) PlaybackStateCompat.STATE_PLAYING
        else PlaybackStateCompat.STATE_PAUSED

        val pb = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_STOP or
                    PlaybackStateCompat.ACTION_SEEK_TO
            )
            .setState(state, positionMs, 1.0f)
            .build()
        mediaSession.setPlaybackState(pb)
        showNotification()
    }

    private fun showNotification() {
        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession.sessionToken)
            .setShowActionsInCompactView(0, 1, 2)

        val playPauseIcon =
            if (lastPlaying) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play
        val playPauseTitle = if (lastPlaying) "Pause" else "Play"

        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { i ->
            PendingIntent.getActivity(
                this, 0, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(lastTitle.ifEmpty { "Mudita Player" })
            .setContentText(lastArtist ?: "")
            .setSubText(lastAlbum)
            .setStyle(style)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(lastPlaying)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                    )
                )
            )
            .addAction(
                NotificationCompat.Action(
                    playPauseIcon, playPauseTitle,
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this, PlaybackStateCompat.ACTION_PLAY_PAUSE
                    )
                )
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                    )
                )
            )
            .setDeleteIntent(
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_STOP
                )
            )

        if (tapIntent != null) builder.setContentIntent(tapIntent)

        val notification = builder.build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "startForeground failed", t)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val chan = NotificationChannel(
                    CHANNEL_ID,
                    "Music playback",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Shows what Mudita Player is currently playing"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(chan)
            }
        }
    }

    private fun sendAction(action: String) {
        // The exception can fire INSIDE the posted runnable (e.g. the Flutter
        // event sink is closed because the app was backgrounded), so the
        // try/catch must be inside the post — otherwise it crashes the app.
        tapHandler.post {
            try {
                eventSink?.success(action)
            } catch (t: Throwable) {
                Log.w(TAG, "sendAction failed", t)
            }
        }
    }

    fun stopAndRelease() {
        try {
            mediaSession.isActive = false
            mediaSession.release()
        } catch (_: Throwable) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        instance = null
        try {
            mediaSession.release()
        } catch (_: Throwable) {}
        super.onDestroy()
    }
}
