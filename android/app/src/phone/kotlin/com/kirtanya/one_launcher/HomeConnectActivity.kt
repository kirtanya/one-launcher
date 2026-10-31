package com.kirtanya.one_launcher

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** Transparent host for the Home APIs permission flow; reports back to [SmartHomeBridge] and closes. */
class HomeConnectActivity : ComponentActivity() {
    private var started = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        started = savedInstanceState?.getBoolean("started") ?: false
        val client = SmartHomeBridge.client()
        if (client == null) {
            SmartHomeBridge.permissionFlowDone("Smart home isn't ready")
            finish()
            return
        }
        // Must be registered before the activity reaches STARTED.
        client.registerActivityResultCallerForPermissions(this)
        if (started) return // recreated mid-flow: the result callback is delivered to the registry
        started = true
        lifecycleScope.launch {
            val error = SmartHomeBridge.requestPermissions(client)
            SmartHomeBridge.permissionFlowDone(error)
            finish()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean("started", started)
    }
}
