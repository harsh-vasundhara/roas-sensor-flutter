package com.roassensor.roas_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.roassensor.sdk.Roas
import com.roassensor.sdk.RoasEvent
import com.roassensor.sdk.RoasLogLevel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The Android half of the `roas_flutter` bridge. Every method here is a thin
 * pass-through to [Roas] (`roas-android-sdk`'s public entry point) — no
 * retry/queueing/hashing logic is duplicated here; that all still lives in
 * the native SDK, exactly as it does for a pure-Kotlin app.
 */
class RoasFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var deliveryChannel: EventChannel
    private lateinit var appContext: Context

    /// Dart's listener, and the handler that feeds it. Held so it can be
    /// detached: the native SDK's callback is a process-wide singleton, and
    /// leaving it pointing at a dead engine's sink leaks the engine and throws
    /// on the first delivery after a hot restart.
    private var deliverySink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "roas_flutter")
        channel.setMethodCallHandler(this)

        deliveryChannel = EventChannel(binding.binaryMessenger, "roas_flutter/delivery")
        deliveryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deliverySink = events
                Roas.setOnDeliveryResult { path, success, error ->
                    // Transport delivers on its own executor; a platform channel
                    // may only be touched from the main thread, and violating
                    // that crashes rather than misbehaves.
                    mainHandler.post {
                        deliverySink?.success(
                            mapOf("path" to path, "success" to success, "error" to error)
                        )
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                Roas.setOnDeliveryResult(null)
                deliverySink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        deliveryChannel.setStreamHandler(null)
        Roas.setOnDeliveryResult(null)
        deliverySink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val publicKey = call.argument<String>("publicKey")
                if (publicKey == null) {
                    result.error("MISSING_ARG", "publicKey is required", null)
                    return
                }
                val customerUserId = call.argument<String>("customerUserId")
                val baseUrl = call.argument<String>("baseUrl")
                val appSecret = call.argument<String>("appSecret")
                // NAMED arguments, not positional. These used to be positional,
                // which meant a new parameter added anywhere but the end of
                // Roas.initialize() silently rebound every one of them by a slot
                // — and still compiled, because the types line up. The result was
                // beacons signed with the customer's user id and posted to the
                // production host instead of the configured one. Named arguments
                // make that class of break a compile error instead of a mystery.
                if (baseUrl != null) {
                    Roas.initialize(
                        context = appContext,
                        publicKey = publicKey,
                        customerUserId = customerUserId,
                        baseUrl = baseUrl,
                        appSecret = appSecret,
                    )
                } else {
                    Roas.initialize(
                        context = appContext,
                        publicKey = publicKey,
                        customerUserId = customerUserId,
                        appSecret = appSecret,
                    )
                }
                result.success(null)
            }

            "visitorId" -> result.success(Roas.visitorId())

            // iOS-only concept: StoreKit's appAccountToken must be a UUID, so the
            // iOS SDK derives one from the vid. Play Billing has no such
            // constraint — its obfuscatedAccountId takes the visitor id verbatim —
            // so Android answers null and callers use visitorId() there. Handled
            // explicitly rather than falling through to notImplemented(), which
            // would surface as a MissingPluginException on a perfectly valid call.
            "appAccountToken" -> result.success(null)

            // Both iOS-only, and both answered rather than left to
            // notImplemented(): Dart guards them with Platform.isIOS, but a
            // MissingPluginException from a method the plugin genuinely has is a
            // confusing way to say "not applicable here". ATT and SKAdNetwork
            // have no Android equivalent — Android's consent story is the AD_ID
            // permission, which is a manifest concern, not a runtime one.
            "requestTracking" -> result.success(null)
            "updateConversionValue" -> result.success(null)

            "identify" -> {
                Roas.identify(
                    email = call.argument<String>("email"),
                    phone = call.argument<String>("phone"),
                    customerUserId = call.argument<String>("customerUserId"),
                )
                result.success(null)
            }

            "track" -> {
                val eventKey = call.argument<String>("event")
                if (eventKey == null) {
                    result.error("MISSING_ARG", "event is required", null)
                    return
                }
                // Anything not in the RoasEvent taxonomy is still tracked — as a
                // custom event named exactly what the caller passed, mirroring
                // Roas.track(RoasEvent.CUSTOM, name = "...") in the native sample.
                val known = RoasEvent.values().find { it.key == eventKey }
                @Suppress("UNCHECKED_CAST")
                val properties = call.argument<Map<String, Any>>("properties")
                if (known != null) {
                    Roas.track(known, properties = properties)
                } else {
                    Roas.track(RoasEvent.CUSTOM, name = eventKey, properties = properties)
                }
                result.success(null)
            }

            "handleDeepLink" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("MISSING_ARG", "url is required", null)
                    return
                }
                Roas.handleDeepLink(url)
                result.success(null)
            }

            "setLogLevel" -> {
                val level = call.argument<String>("level")
                    ?.let { runCatching { RoasLogLevel.valueOf(it) }.getOrNull() }
                    ?: RoasLogLevel.ERROR
                Roas.setLogLevel(level)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
