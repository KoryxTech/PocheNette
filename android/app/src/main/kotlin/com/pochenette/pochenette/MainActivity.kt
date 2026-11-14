package com.pochenette.pochenette

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
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
        val secure = getSharedPreferences("pochenette_secure", MODE_PRIVATE)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pochenette/local")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(state.getString("state", null))
                "save" -> {
                    val saved = state.edit().putString("state", call.arguments as String).commit()
                    if (saved) result.success(null) else result.error("SAVE", "Écriture impossible", null)
                }
                "secureGet" -> result.success(secure.getString(call.arguments as String, null))
                "secureSet" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val key = args?.get("key") as? String
                    if (key.isNullOrEmpty()) {
                        result.error("SECURE", "Clé manquante", null)
                    } else {
                        val value = args?.get("value") as? String
                        val editor = secure.edit()
                        if (value == null) editor.remove(key) else editor.putString(key, value)
                        if (editor.commit()) result.success(true)
                        else result.error("SECURE", "Écriture sécurisée impossible", null)
                    }
                }
                "dialUssd" -> {
                    try {
                        val code = call.arguments as String
                        val encoded = Uri.encode(code)
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$encoded"))
                        startActivity(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("DIAL", "Impossible d’ouvrir le composeur", null)
                    }
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
