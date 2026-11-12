package com.dewdew.pressframe

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Open settings" on the gallery-permission screen: shows this app's settings page.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pressframe/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        )
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
