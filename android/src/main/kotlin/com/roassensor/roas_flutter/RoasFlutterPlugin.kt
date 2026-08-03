package com.roassensor.roas_flutter

import android.content.Context
import com.roassensor.sdk.Roas
import com.roassensor.sdk.RoasEvent
import com.roassensor.sdk.RoasLogLevel
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "roas_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
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
                if (baseUrl != null) {
                    Roas.initialize(appContext, publicKey, customerUserId, baseUrl)
                } else {
                    Roas.initialize(appContext, publicKey, customerUserId)
                }
                result.success(null)
            }

            "visitorId" -> result.success(Roas.visitorId())

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
