package com.spendwise.spendwise

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine, and answers the one platform call this app makes.
 *
 * FLAG_SECURE keeps the window out of screenshots, screen recordings and the
 * thumbnail Android shows in the recents list. Dart turns it on while a screen
 * that shows money is in the tree and off again when the last one goes, so the
 * flag follows the customer rather than being set once and forgotten.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_FLAG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val SECURE_FLAG_CHANNEL = "spendwise/secure_flag"
    }
}
