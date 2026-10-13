package com.muditakompakt.mudita_player

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Hardware-key gesture detection.
 *
 * Single press of volume up/down passes through to the system as normal
 * volume control. We only consume LONG PRESS (held >600ms) and DOUBLE TAP
 * (two presses within 350ms) on the volume buttons, and forward those to
 * Dart for the user-configured action.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "main"
        private const val MEDIA_CONTROL_CHANNEL = "com.muditakompakt.mudita_player/media_control"
        private const val MEDIA_EVENT_CHANNEL = "com.muditakompakt.mudita_player/media_events"

        // Kept outside the activity: with the cached engine, Dart only sends
        // this once, but the activity can be recreated many times.
        @Volatile
        private var enabled = true

        // The activity on screen, if any. Only the battery prompt needs one.
        @Volatile
        private var liveActivity: WeakReference<MainActivity>? = null

        // The media channels live as long as the cached engine, so they are
        // set up once, here, with the application context. Handlers set from
        // the activity kept every closed activity in memory.
        private fun registerMediaChannels(engine: FlutterEngine, app: Context) {
            try {
                // Dart -> Kotlin: push playback state to the system MediaSession.
                MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    MEDIA_CONTROL_CHANNEL,
                ).setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "start" -> {
                                app.startService(Intent(app, MediaPlaybackService::class.java))
                                result.success(null)
                            }
                            "stop" -> {
                                MediaPlaybackService.instance?.stopAndRelease()
                                app.stopService(Intent(app, MediaPlaybackService::class.java))
                                result.success(null)
                            }
                            "setMetadata" -> {
                                val args = call.arguments as Map<*, *>
                                MediaPlaybackService.instance?.updateMetadata(
                                    title = args["title"] as? String ?: "",
                                    artist = args["artist"] as? String,
                                    album = args["album"] as? String,
                                    durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0L,
                                    artPath = args["artPath"] as? String,
                                )
                                result.success(null)
                            }
                            "setPlaybackState" -> {
                                val args = call.arguments as Map<*, *>
                                MediaPlaybackService.instance?.updatePlaybackState(
                                    playing = args["playing"] as? Boolean ?: false,
                                    positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L,
                                )
                                result.success(null)
                            }
                            "isBatteryExempt" -> {
                                result.success(isIgnoringBatteryOptimizations(app))
                            }
                            "requestBatteryExemption" -> {
                                // With no activity on screen there is nothing to
                                // show the prompt from; just report the state.
                                liveActivity?.get()?.requestBatteryExemption()
                                result.success(isIgnoringBatteryOptimizations(app))
                            }
                            else -> result.notImplemented()
                        }
                    } catch (t: Throwable) {
                        result.error("err", t.message, null)
                    }
                }

                // Kotlin -> Dart: button presses from the lock screen, car and
                // headphones.
                EventChannel(
                    engine.dartExecutor.binaryMessenger,
                    MEDIA_EVENT_CHANNEL,
                ).setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        MediaPlaybackService.eventSink = events
                    }
                    override fun onCancel(arguments: Any?) {
                        MediaPlaybackService.eventSink = null
                    }
                })
            } catch (_: Throwable) {
                // Don't let channel setup crash the app.
            }
        }

        private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    pm.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true
                }
            } catch (_: Throwable) {
                false
            }
        }
    }

    private val channelName = "com.muditakompakt.mudita_player/hwkeys"
    private var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val multiTapWindowMs = 350L
    private val longPressMs = 600L

    private var lastTapKeyCode = 0
    private var lastTapTime = 0L
    private var pendingTapRunnable: Runnable? = null
    private var longPressFiredForKey = 0
    private var pendingLongPressRunnable: Runnable? = null

    // One engine for the whole process. It is not destroyed with the
    // activity, so swiping the app from Recents leaves the music playing.
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        registerMediaChannels(engine, app)
        cache.put(ENGINE_ID, engine)
        return engine
    }

    // Back on the first screen hides the app instead of finishing it, so
    // playback carries on.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        liveActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
        // Route volume buttons to the media stream so they always change
        // music volume, not ringtone or notification volume.
        try {
            volumeControlStream = AudioManager.STREAM_MUSIC
        } catch (_: Throwable) {
        }
    }

    override fun onDestroy() {
        if (liveActivity?.get() === this) liveActivity = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        enabled = (call.arguments as? Boolean) ?: true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        } catch (t: Throwable) {
            // Don't let channel setup crash the activity.
        }
    }

    private fun requestBatteryExemption() {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            if (isIgnoringBatteryOptimizations(this)) return
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (_: Throwable) {
            // Fall back to the general battery optimization settings list.
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Throwable) {}
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        return try {
            handleKeyEvent(event)
        } catch (t: Throwable) {
            super.dispatchKeyEvent(event)
        }
    }

    private fun handleKeyEvent(event: KeyEvent): Boolean {
        if (!enabled) return super.dispatchKeyEvent(event)
        val k = event.keyCode
        if (!isInterceptable(k)) return super.dispatchKeyEvent(event)

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    pendingLongPressRunnable?.let { mainHandler.removeCallbacks(it) }
                    val r = Runnable {
                        longPressFiredForKey = k
                        emit("longPress", k)
                    }
                    pendingLongPressRunnable = r
                    mainHandler.postDelayed(r, longPressMs)
                }
                // Don't consume — allow system to begin volume change. We'll
                // cancel the pending action on KeyUp if the press was short.
                return super.dispatchKeyEvent(event)
            }
            KeyEvent.ACTION_UP -> {
                pendingLongPressRunnable?.let { mainHandler.removeCallbacks(it) }
                if (longPressFiredForKey == k) {
                    longPressFiredForKey = 0
                    // Long press was already emitted; let UP through normally.
                    return super.dispatchKeyEvent(event)
                }
                val now = System.currentTimeMillis()
                val sameKey = lastTapKeyCode == k
                val withinWindow = (now - lastTapTime) <= multiTapWindowMs
                if (sameKey && withinWindow) {
                    pendingTapRunnable?.let { mainHandler.removeCallbacks(it) }
                    pendingTapRunnable = null
                    lastTapKeyCode = 0
                    lastTapTime = 0
                    emit("doubleTap", k)
                    // Consume — we acted on the gesture.
                    return true
                } else {
                    lastTapKeyCode = k
                    lastTapTime = now
                    val captured = k
                    val r = Runnable {
                        if (lastTapKeyCode == captured) {
                            lastTapKeyCode = 0
                            lastTapTime = 0
                        }
                    }
                    pendingTapRunnable = r
                    mainHandler.postDelayed(r, multiTapWindowMs)
                    return super.dispatchKeyEvent(event)
                }
            }
            else -> return super.dispatchKeyEvent(event)
        }
    }

    private fun isInterceptable(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            keyCode == KeyEvent.KEYCODE_CAMERA ||
            keyCode == KeyEvent.KEYCODE_HEADSETHOOK ||
            keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
            keyCode == KeyEvent.KEYCODE_MEDIA_NEXT ||
            keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS
    }

    private fun emit(gesture: String, keyCode: Int) {
        channel?.invokeMethod(
            "hwKey",
            mapOf(
                "gesture" to gesture,
                "keyCode" to keyCode,
            ),
        )
    }
}
