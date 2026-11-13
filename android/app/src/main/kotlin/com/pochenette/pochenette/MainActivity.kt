package com.pochenette.pochenette

import android.Manifest
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pendingPermission: MethodChannel.Result? = null
    private var observing = false
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (::channel.isInitialized) channel.invokeMethod("inboxChanged", null)
        }
    }

    private fun canRead() = checkSelfPermission(Manifest.permission.READ_SMS) ==
        PackageManager.PERMISSION_GRANTED

    private fun observeInbox() {
        if (!observing && canRead()) {
            contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
            observing = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val state = getSharedPreferences("pochenette", MODE_PRIVATE)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pochenette/local")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(state.getString("state", null))
                "save" -> {
                    val saved = state.edit().putString("state", call.arguments as String).commit()
                    if (saved) result.success(null) else result.error("SAVE", "Écriture impossible", null)
                }
                "permission" -> result.success(canRead())
                "requestPermission" -> when {
                    canRead() -> { observeInbox(); result.success(true) }
                    pendingPermission != null -> result.error("PENDING", "Demande en cours", null)
                    else -> {
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.READ_SMS), 42)
                    }
                }
                "readInbox" -> {
                    if (!canRead()) {
                        result.error("PERMISSION", "Accès aux SMS désactivé", null)
                    } else {
                        observeInbox()
                        Thread {
                            try {
                                val receipts = readInbox((call.arguments as Number).toLong())
                                runOnUiThread { result.success(receipts) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("INBOX", "Lecture des SMS impossible", null) }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readInbox(since: Long): List<Map<String, Any>> {
        val receipts = mutableListOf<Map<String, Any>>()
        val columns = arrayOf("_id", "address", "body", "date")
        val senders = arrayOf("orangemoney", "orange money", "mtnmomo", "mtn momo", "momo", "mobilemoney", "mobile money")
        val placeholders = senders.joinToString(",") { "?" }
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI, columns,
            "date >= ? AND LOWER(address) IN ($placeholders)",
            arrayOf(since.toString(), *senders), "date ASC, _id ASC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                receipts.add(mapOf(
                    "id" to cursor.getString(0),
                    "sender" to cursor.getString(1),
                    "body" to cursor.getString(2),
                    "date" to cursor.getLong(3)
                ))
            }
        }
        return receipts
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 42) {
            observeInbox()
            pendingPermission?.success(canRead())
            pendingPermission = null
        }
    }

    override fun onDestroy() {
        if (observing) contentResolver.unregisterContentObserver(observer)
        super.onDestroy()
    }
}
