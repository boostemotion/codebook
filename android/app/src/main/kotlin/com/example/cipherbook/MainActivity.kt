package com.example.cipherbook

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    private fun preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        val display = windowManager.defaultDisplay
        val currentMode = display.mode
        val mode = display.supportedModes
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
            ?: return

        val attributes = window.attributes
        if (attributes.preferredDisplayModeId != mode.modeId) {
            attributes.preferredDisplayModeId = mode.modeId
            window.attributes = attributes
        }
    }
}
