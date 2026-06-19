package com.example.labmembers

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.webkit.*
import androidx.activity.ComponentActivity
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private var fileUploadCallback: ValueCallback<Array<Uri>>? = null
    private val FILE_CHOOSER_REQUEST_CODE = 1001
    private val PERMISSIONS_REQUEST_CODE = 1002
    private val CHANNEL_ID = "lab_members_chat"
    private val CHANNEL_NAME = "Lab Members Chat Notifications"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        createNotificationChannel()
        
        val container = android.widget.FrameLayout(this)
        container.fitsSystemWindows = true
        
        webView = WebView(this)
        webView.layoutParams = android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        )
        
        container.addView(webView)
        setContentView(container)

        // Expose JavaScript Interface for local notifications
        webView.addJavascriptInterface(WebAppInterface(this), "AndroidBridge")

        // Configure WebView settings
        val settings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        settings.allowFileAccessFromFileURLs = true
        settings.allowUniversalAccessFromFileURLs = true
        settings.cacheMode = WebSettings.LOAD_DEFAULT

        // Fix Error 403: disallowed_useragent for Google Login
        val defaultUserAgent = settings.userAgentString
        if (defaultUserAgent != null) {
            val customUserAgent = defaultUserAgent
                .replace("; wv", "")
                .replace("Version/4.0 ", "")
            settings.userAgentString = customUserAgent
        } else {
            settings.userAgentString = "Mozilla/5.0 (Linux; Android 13; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
        }

        // Handle page navigation
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                
                // If it is Supabase Google Auth, open in external browser (Google Chrome)
                if (url.contains("supabase.co/auth/v1/authorize") && url.contains("provider=google")) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        return true
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                if (url.startsWith("http://") || url.startsWith("https://") || url.startsWith("file://")) {
                    view?.loadUrl(url)
                } else {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(intent)
                    } catch (e: Exception) {
                        // Ignore invalid deep links
                    }
                }
                return true
            }
        }

        // Handle WebChromeClient features (microphone/camera permissions and file chooser)
        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                if (consoleMessage != null) {
                    android.util.Log.e("WebViewJS", "${consoleMessage.messageLevel()}: ${consoleMessage.message()} -- From line ${consoleMessage.lineNumber()} of ${consoleMessage.sourceId()}")
                }
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.grant(request?.resources)
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                fileUploadCallback?.onReceiveValue(null)
                fileUploadCallback = filePathCallback

                val intent = fileChooserParams?.createIntent()
                if (intent != null) {
                    try {
                        startActivityForResult(intent, FILE_CHOOSER_REQUEST_CODE)
                    } catch (e: ActivityNotFoundException) {
                        fileUploadCallback = null
                        return false
                    }
                } else {
                    fileUploadCallback = null
                    return false
                }
                return true
            }
        }

        // Load the login page as the entry point
        webView.loadUrl("file:///android_asset/login.html")

        // Request runtime permissions on launch for maximum user experience
        requestSystemPermissions()

        // Handle deep link on launch
        handleDeepLink(intent)

        // Start persistent background service for notifications
        startBackgroundService()
    }

    private fun startBackgroundService() {
        try {
            val serviceIntent = Intent(this, BackgroundService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun requestSystemPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val neededPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (neededPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, neededPermissions.toTypedArray(), PERMISSIONS_REQUEST_CODE)
        }
    }

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = "New message alerts for Lab Members"
                enableLights(true)
                lightColor = Color.GREEN
                enableVibration(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
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

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setSound(defaultSoundUri)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)

        notificationManager.notify(System.currentTimeMillis().toInt(), notificationBuilder.build())
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            val results = WebChromeClient.FileChooserParams.parseResult(resultCode, data)
            fileUploadCallback?.onReceiveValue(results)
            fileUploadCallback = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val dataStr = intent?.data?.toString()
        if (dataStr != null && dataStr.startsWith("com.example.labmembers://login")) {
            var suffix = dataStr.substring("com.example.labmembers://login".length)
            if (suffix.startsWith("?")) {
                suffix = "#" + suffix.substring(1)
            }
            webView.loadUrl("file:///android_asset/login.html$suffix")
        }
    }

    override fun onBackPressed() {
        webView.evaluateJavascript("javascript:(function() { if(typeof window.onBackPressed === 'function') { return window.onBackPressed(); } return false; })()") { result ->
            if (result == "false" || result == null) {
                runOnUiThread {
                    val url = webView.url
                    if (url != null && url.contains("chat-prototype_1.html")) {
                        // Minimize app to background instead of closing or loading login screen
                        moveTaskToBack(true)
                    } else {
                        if (webView.canGoBack()) {
                            webView.goBack()
                        } else {
                            super.onBackPressed()
                        }
                    }
                }
            }
        }
    }

    class WebAppInterface(private val activity: MainActivity) {
        @JavascriptInterface
        fun sendNotification(title: String, message: String) {
            activity.runOnUiThread {
                activity.showLocalNotification(title, message)
            }
        }

        @JavascriptInterface
        fun saveAuthSession(token: String, refreshToken: String, userId: String, email: String) {
            val sharedPref = activity.getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE)
            with (sharedPref.edit()) {
                putString("accessToken", token)
                putString("refreshToken", refreshToken)
                putString("userId", userId)
                putString("userEmail", email)
                apply()
            }
            // Start or update background listener service with new credentials
            activity.runOnUiThread {
                activity.startBackgroundService()
            }
        }

        @JavascriptInterface
        fun saveAuthSession(token: String, userId: String, email: String) {
            saveAuthSession(token, "", userId, email)
        }

        @JavascriptInterface
        fun getSavedAuthSession(): String {
            val sharedPref = activity.getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE)
            val accessToken = sharedPref.getString("accessToken", "") ?: ""
            val refreshToken = sharedPref.getString("refreshToken", "") ?: ""
            val userId = sharedPref.getString("userId", "") ?: ""
            val email = sharedPref.getString("userEmail", "") ?: ""
            
            val json = org.json.JSONObject().apply {
                put("accessToken", accessToken)
                put("refreshToken", refreshToken)
                put("userId", userId)
                put("email", email)
            }
            return json.toString()
        }

        @JavascriptInterface
        fun clearAuthSession() {
            val sharedPref = activity.getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE)
            with (sharedPref.edit()) {
                remove("accessToken")
                remove("refreshToken")
                remove("userId")
                remove("userEmail")
                apply()
            }
            // Stop the background service immediately
            try {
                val serviceIntent = Intent(activity, BackgroundService::class.java)
                activity.stopService(serviceIntent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        @JavascriptInterface
        fun openBatterySettings() {
            try {
                val intent = Intent().apply {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        action = android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                    } else {
                        action = android.provider.Settings.ACTION_SETTINGS
                    }
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                activity.startActivity(intent)
            } catch (e: Exception) {
                try {
                    val fallback = Intent(android.provider.Settings.ACTION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    activity.startActivity(fallback)
                } catch (ex: Exception) {
                    ex.printStackTrace()
                }
            }
        }

        @JavascriptInterface
        fun saveIdentityIds(ids: String) {
            val sharedPref = activity.getSharedPreferences("LabMembersPrefs", Context.MODE_PRIVATE)
            with (sharedPref.edit()) {
                putString("identityIds", ids)
                apply()
            }
        }
    }
}
