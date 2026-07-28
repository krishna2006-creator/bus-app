package com.agni.bus.tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * MyFirebaseMessagingService handles all FCM push notifications.
 *
 * - onNewToken: Called when a new FCM token is generated for this device.
 *   Logs the token so it can be sent to the backend for targeting.
 *
 * - onMessageReceived: Called when a data or notification message is
 *   received while the app is in the foreground (or when the app is
 *   killed and a data-only message arrives).
 *
 * This service is registered in AndroidManifest.xml.
 */
class MyFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "MyFirebaseMsgService"
        private const val CHANNEL_ID = "bus_tracking_channel"
        private const val CHANNEL_NAME = "Bus Tracking Notifications"
        private const val CHANNEL_DESC = "Notifications for bus tracking updates and alerts"
    }

    /**
     * Called when the FCM registration token is refreshed.
     * This happens:
     *  - On initial app launch
     *  - After app reinstall
     *  - When the user clears app data
     *  - Periodically (token rotation)
     */
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "FCM Token refreshed: $token")

        // Send the token to the backend so it can target this device
        sendTokenToBackend(token)
    }

    /**
     * Called when a message is received while the app is in the foreground
     * or when a data-only message arrives (even if the app is in the background
     * or killed, as long as the message has a "data" payload).
     *
     * For notification messages (with "notification" payload) received while
     * the app is in the background, the system tray handles display and this
     * method is NOT called. For foreground delivery, use
     * setForegroundNotificationPresentationOptions on the Flutter side.
     */
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.d(TAG, "FCM Message received from: ${remoteMessage.from}")

        // Check if message contains a data payload
        if (remoteMessage.data.isNotEmpty()) {
            Log.d(TAG, "FCM Message data payload: ${remoteMessage.data}")
            handleNow(remoteMessage.data)
        }

        // Check if message contains a notification payload
        remoteMessage.notification?.let {
            Log.d(TAG, "FCM Notification Title: ${it.title}")
            Log.d(TAG, "FCM Notification Body: ${it.body}")

            // Display the notification
            showNotification(
                title = it.title ?: getString(R.string.app_name),
                body = it.body ?: "",
                clickAction = it.clickAction,
                data = remoteMessage.data
            )
        }
    }

    /**
     * Handle the data payload immediately (e.g., trigger a local action).
     * This is called when the app is in the foreground.
     */
    private fun handleNow(data: Map<String, String>) {
        Log.d(TAG, "Handling FCM data payload: $data")

        // Example: Extract custom keys from data
        val busId = data["bus_id"]
        val busNumber = data["bus_number"]
        val category = data["category"]

        Log.d(TAG, "Bus ID: $busId, Bus Number: $busNumber, Category: $category")

        // If you need to perform background work, schedule it via
        // WorkManager to comply with Android background execution limits.
    }

    /**
     * Display a notification in the system tray.
     */
    private fun showNotification(
        title: String,
        body: String,
        clickAction: String?,
        data: Map<String, String>
    ) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create the notification channel (required for Android 8.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESC
                enableLights(true)
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Set the default sound
        val defaultSoundUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        // Create an intent to open the app when the notification is tapped
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            // Pass any data from the notification
            data.forEach { (key, value) -> putExtra(key, value) }
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingIntentFlags)

        // Build the notification
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification) // Replace with your app's notification icon
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setSound(defaultSoundUri)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)

        // Show the notification
        val notificationId = System.currentTimeMillis().toInt()
        notificationManager.notify(notificationId, notificationBuilder.build())

        Log.d(TAG, "Notification displayed: $title - $body")
    }

    /**
     * Send the FCM token to your backend server so it can target
     * this device with push notifications.
     *
     * Replace the API endpoint and auth logic as needed for your app.
     */
    private fun sendTokenToBackend(token: String) {
        Log.d(TAG, "Sending FCM token to backend: $token")

        // TODO: Replace with your actual backend API call
        // Example using OkHttp or your preferred HTTP client:
        //
        // val client = OkHttpClient()
        // val json = """{"token": "$token", "platform": "android"}"""
        // val request = Request.Builder()
        //     .url("https://your-backend.com/api/notifications/device-token")
        //     .post(RequestBody.create(json, MediaType.get("application/json")))
        //     .build()
        // client.newCall(request).enqueue(...)
    }
}
</arg_value>
<task_progress>
- [x] Analyze project structure and existing code
- [x] Update backend serviceAccountKey.json with bustracker-afb3c credentials
- [x] Update backend config.py with correct FCM project ID and sender ID
- [ ] Create FastAPI /send-notification endpoint using firebase-admin SDK (HTTP v1)
- [x] Create Android Kotlin MyFirebaseMessagingService class
- [ ] Update AndroidManifest.xml with notification service registration
- [ ] Verify google-services.json and gradle dependencies
- [ ] Final verification of all integration points
</task_progress></tool_call>