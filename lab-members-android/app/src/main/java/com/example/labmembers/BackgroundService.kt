package com.example.labmembers

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.RingtoneManager
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

import android.os.PowerManager
import java.io.OutputStream

class BackgroundService : Service() {
    private val FOREGROUND_NOTIFICATION_ID = 2001
    private val NOTIFICATION_CHANNEL_ID = "lab_members_background"
    private val CHAT_CHANNEL_ID = "lab_members_chat"
    
    private var scheduler: ScheduledExecutorService? = null
    private var wakeLock: PowerManager.WakeLock? = null

    class ApiException(val code: Int, message: String) : Exception(message)

    override fun onCreate() {
        super.onCreate()
        
        // Acquire partial WakeLock to keep CPU running when screen is off
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LabMembers::BackgroundServiceWakeLock").apply {
                acquire()
            }
            android.util.Log.d("BgService", "WakeLock acquired successfully")
        } catch (e: Exception) {
            android.util.Log.e("BgService", "Failed to acquire WakeLock", e)
        }

        createNotificationChannels()
        startServiceForeground()
        startPolling()
    }

    private fun startServiceForeground() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Lab Members")
            .setContentText("مستعد لاستقبال الرسائل في الخلفية...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(FOREGROUND_NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannels() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val fgChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Lab Members Background Listener",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps the app listening for new messages"
                enableLights(false)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(fgChannel)

            val chatChannel = NotificationChannel(
                CHAT_CHANNEL_ID,
                "Lab Members Chat Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New message alerts for Lab Members"
                enableLights(true)
                lightColor = Color.GREEN
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(chatChannel)
        }
    }

    private fun startPolling() {
        scheduler = Executors.newSingleThreadScheduledExecutor()
        scheduler?.scheduleWithFixedDelay({
            try {
                pollSupabaseMessages()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, 2, 8, TimeUnit.SECONDS)
    }

    private fun pollSupabaseMessages() {
        val sharedPref = getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE)
        var accessToken = sharedPref.getString("accessToken", null) ?: return
        val userId = sharedPref.getString("userId", null) ?: return

        // 1. Fetch latest messages received by my account (highly RLS-compliant)
        val urlStr = "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/messages?select=*&receiver_id=eq.$userId&order=created_at.desc&limit=5"
        
        var response: String? = null
        try {
            response = makeHttpGet(urlStr, accessToken)
        } catch (authEx: ApiException) {
            android.util.Log.e("BgServicePoll", "Access token expired (401/403). Attempting automatic refresh...")
            val refreshToken = sharedPref.getString("refreshToken", null)
            if (!refreshToken.isNullOrEmpty()) {
                val refreshed = refreshAccessToken(refreshToken)
                if (refreshed != null) {
                    val newAccess = refreshed.first
                    val newRefresh = refreshed.second
                    accessToken = newAccess
                    sharedPref.edit().apply {
                        putString("accessToken", newAccess)
                        if (newRefresh.isNotEmpty()) {
                            putString("refreshToken", newRefresh)
                        }
                        apply()
                    }
                    android.util.Log.d("BgServicePoll", "Token refreshed successfully! Retrying request...")
                    try {
                        response = makeHttpGet(urlStr, newAccess)
                    } catch (retryEx: Exception) {
                        android.util.Log.e("BgServicePoll", "Retry after token refresh failed", retryEx)
                    }
                } else {
                    android.util.Log.e("BgServicePoll", "Automatic token refresh returned null")
                }
            } else {
                android.util.Log.e("BgServicePoll", "No refresh token available in preferences")
            }
        } catch (e: Exception) {
            android.util.Log.e("BgServicePoll", "HTTP request failed with general exception", e)
        }

        if (response.isNullOrEmpty()) return
        
        val messagesArray = JSONArray(response)
        if (messagesArray.length() == 0) return

        val notifiedIds = sharedPref.getStringSet("notifiedMessageIds", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        // Priming logic: if cache is empty, we just load existing messages silently
        val isFirstRun = notifiedIds.isEmpty()
        var hasNewNotification = false

        for (i in 0 until messagesArray.length()) {
            val msg = messagesArray.getJSONObject(i)
            val id = msg.getString("id")
            val senderId = msg.getString("sender_id")
            
            // Ignore my own messages
            if (senderId == userId) continue
            
            // Ignore if already notified
            if (notifiedIds.contains(id)) continue

            // Mark as notified
            notifiedIds.add(id)
            hasNewNotification = true

            // Skip showing notification during first run priming
            if (isFirstRun) {
                android.util.Log.e("BgServicePoll", "Primed historical message ID: $id")
                continue
            }

            android.util.Log.e("BgServicePoll", "New message detected! Showing alert for ID: $id")

            // Fetch sender profile name
            val senderProfileUrl = "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/profiles?select=*&id=eq.$senderId"
            var profileResponse: String? = null
            try {
                val currentToken = getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE).getString("accessToken", accessToken) ?: accessToken
                profileResponse = makeHttpGet(senderProfileUrl, currentToken)
            } catch (e: Exception) {
                android.util.Log.e("BgServicePoll", "Failed to fetch profile due to auth/network, fallback to default name", e)
            }
            var senderName = "عضو المعمل"
            if (!profileResponse.isNullOrEmpty()) {
                val profilesArray = JSONArray(profileResponse)
                if (profilesArray.length() > 0) {
                    val profile = profilesArray.getJSONObject(0)
                    val fullName = profile.optString("full_name", "")
                    val username = profile.optString("username", "")
                    senderName = if (fullName.isNotEmpty()) fullName else if (username.isNotEmpty()) username else "عضو المعمل"
                }
            }

            // Parse content
            var content = msg.optString("content", "")
            if (content.isEmpty()) {
                content = msg.optString("body", "")
            }
            if (content.isEmpty()) {
                content = msg.optString("text", "رسالة جديدة 💬")
            }

            // Clean reply prefix
            if (content.startsWith("[reply:")) {
                val endIdx = content.indexOf("}]")
                if (endIdx != -1) {
                    content = content.substring(endIdx + 2)
                }
            }

            // Clean media formats
            if (content.startsWith("[image]")) {
                content = "📷 صورة"
            } else if (content.startsWith("[video]")) {
                content = "🎥 فيديو"
            } else if (content.startsWith("[voice")) {
                content = "🎤 ريكورد صوتي"
            }

            // Trigger local high-priority alert
            showLocalNotification(senderName, content)
        }

        if (hasNewNotification || isFirstRun) {
            // Keep the notified list clean (limit to last 100 entries)
            val trimmedList = if (notifiedIds.size > 100) {
                notifiedIds.toList().takeLast(100).toMutableSet()
            } else {
                notifiedIds
            }
            sharedPref.edit().putStringSet("notifiedMessageIds", trimmedList).apply()
        }
    }

    private fun makeHttpGet(urlStr: String, accessToken: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlStr)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("apikey", "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj")
            conn.setRequestProperty("Authorization", "Bearer $accessToken")
            conn.setRequestProperty("Accept-Profile", "public")
            conn.connectTimeout = 6000
            conn.readTimeout = 6000

            val responseCode = conn.responseCode
            if (responseCode == HttpURLConnection.HTTP_OK) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val sb = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    sb.append(line)
                }
                reader.close()
                sb.toString()
            } else {
                if (responseCode == 401 || responseCode == 403) {
                    throw ApiException(responseCode, "Authentication failed")
                }
                val errorStream = conn.errorStream
                if (errorStream != null) {
                    val reader = BufferedReader(InputStreamReader(errorStream))
                    val errorSb = StringBuilder()
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        errorSb.append(line)
                    }
                    reader.close()
                    android.util.Log.e("BgServiceHttp", "Error response for $urlStr (Code $responseCode): ${errorSb.toString()}")
                } else {
                    android.util.Log.e("BgServiceHttp", "Error response for $urlStr (Code $responseCode), no error stream")
                }
                null
            }
        } catch (e: ApiException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.e("BgServiceHttp", "Exception for $urlStr", e)
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun refreshAccessToken(refreshToken: String): Pair<String, String>? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("https://fetmbjnehfdtousenflp.supabase.co/auth/v1/token?grant_type=refresh_token")
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("apikey", "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true

            val body = JSONObject().apply {
                put("refresh_token", refreshToken)
            }.toString()

            conn.outputStream.use { os ->
                os.write(body.toByteArray(Charsets.UTF_8))
            }

            val responseCode = conn.responseCode
            if (responseCode == HttpURLConnection.HTTP_OK) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val sb = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    sb.append(line)
                }
                reader.close()
                val json = JSONObject(sb.toString())
                val newAccess = json.optString("access_token", "")
                val newRefresh = json.optString("refresh_token", "")
                if (newAccess.isNotEmpty()) {
                    Pair(newAccess, newRefresh)
                } else {
                    null
                }
            } else {
                android.util.Log.e("BgServiceHttp", "Failed to refresh token: Code $responseCode")
                null
            }
        } catch (e: Exception) {
            android.util.Log.e("BgServiceHttp", "Exception refreshing token", e)
            null
        } finally {
            conn?.disconnect()
        }
    }

    fun showLocalNotification(title: String, message: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val notificationBuilder = NotificationCompat.Builder(this, CHAT_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setSound(defaultSoundUri)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)

        notificationManager.notify(System.currentTimeMillis().toInt(), notificationBuilder.build())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        scheduler?.shutdownNow()
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onDestroy()
    }
}
