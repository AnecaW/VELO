package com.example.bike_computer

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val appLoader = Executors.newSingleThreadExecutor()
    private var speech: TextToSpeech? = null
    private var notificationResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speech = TextToSpeech(this) { status -> if (status == TextToSpeech.SUCCESS) speech?.language = Locale.getDefault() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bike_computer/device").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(mapOf("version" to info.versionName, "build" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()))
                    }
                    "apps" -> {
                        appLoader.execute {
                            try {
                                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                                val apps = packageManager.queryIntentActivities(intent, 0)
                                    .filter { it.activityInfo.packageName != packageName }
                                    .distinctBy { it.activityInfo.packageName }
                                    .map { info ->
                                        val icon = try {
                                            val drawable = info.loadIcon(packageManager)
                                            val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                                            drawable.setBounds(0, 0, 96, 96)
                                            drawable.draw(Canvas(bitmap))
                                            val bytes = ByteArrayOutputStream()
                                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
                                            bitmap.recycle()
                                            bytes.toByteArray()
                                        } catch (_: Exception) { null }
                                        mapOf("package" to info.activityInfo.packageName,
                                            "name" to info.loadLabel(packageManager).toString(), "icon" to icon)
                                    }.sortedBy { (it["name"] as String).lowercase() }
                                Handler(Looper.getMainLooper()).post { result.success(apps) }
                            } catch (_: Exception) {
                                Handler(Looper.getMainLooper()).post { result.error("apps_unavailable", "Apps konden niet worden geladen", null) }
                            }
                        }
                    }

                    "launch" -> {
                        val pkg = call.arguments as String
                        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: throw IllegalArgumentException("App niet beschikbaar")
                        startActivity(intent); result.success(null)
                    }
                    "pin" -> { startLockTask(); result.success(null) }
                    "unpin" -> { stopLockTask(); result.success(null) }
                    "display" -> {
                        val args = call.arguments as Map<*, *>
                        if (args["keepOn"] == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        val attrs = window.attributes
                        attrs.screenBrightness = (args["brightness"] as? Number)?.toFloat() ?: -1f
                        window.attributes = attrs
                        result.success(null)
                    }
                    "notifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            notificationResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 55)
                        } else result.success(null)
                    }
                    "speak" -> { speech?.speak(call.arguments as String, TextToSpeech.QUEUE_FLUSH, null, "navigation"); result.success(null) }
                    "diagnostics" -> {
                        val battery = getSystemService(BATTERY_SERVICE) as BatteryManager
                        result.success(mapOf("android" to Build.VERSION.RELEASE, "sdk" to Build.VERSION.SDK_INT,
                            "networkAvailable" to ((getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).activeNetwork != null),
                            "battery" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                            "gpsHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS),
                            "bleHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE),
                            "freeBytes" to StatFs(filesDir.absolutePath).availableBytes))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("DEVICE", e.message, null) }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 55) { notificationResult?.success(null); notificationResult = null }
    }
    override fun onDestroy() { appLoader.shutdown(); speech?.stop(); speech?.shutdown(); super.onDestroy() }
}
