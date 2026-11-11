package org.gaccchurch.gpsceilo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    /**
     * Always start at the app's own first screen (splash).
     *
     * FlutterActivity otherwise uses an intent extra named "route" as the
     * initial route, and a tapped push notification carries its `data` (which
     * has a "route" key) as intent extras. That opened e.g. /prayer-list as a
     * bare page with no tab bar and skipped sign-in checks. The tapped route
     * is handled by PushNotificationService once the main app is ready.
     */
    override fun getInitialRoute(): String = "/"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /** The channel push notifications are shown in (see AndroidManifest). */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.default_notification_channel_id),
            getString(R.string.default_notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
