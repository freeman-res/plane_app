package com.example.worknotes

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "worknotes/notes_files"
    private val pickRequest = 101
    private val saveRequest = 102
    private var pending: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("BUSY", "File dialog is already open", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "pick" -> {
                        pending = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "audio/*"))
                        }
                        startActivityForResult(intent, pickRequest)
                    }
                    "save" -> {
                        val name = call.argument<String>("name") ?: "attachment"
                        saveBytes = call.argument<ByteArray>("bytes")
                        if (saveBytes == null) {
                            result.error("FILE", "Missing attachment bytes", null)
                            return@setMethodCallHandler
                        }
                        pending = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(intent, saveRequest)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Required for Android's document picker")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest && requestCode != saveRequest) return
        val callback = pending ?: return
        pending = null
        try {
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                callback.success(null)
            } else if (requestCode == pickRequest) {
                var name = "attachment"
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) name = cursor.getString(column)
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("Cannot read selected file")
                callback.success(mapOf("name" to name, "bytes" to bytes))
            } else {
                contentResolver.openOutputStream(uri)?.use { it.write(saveBytes ?: ByteArray(0)) }
                    ?: throw IllegalStateException("Cannot save attachment")
                callback.success(null)
            }
        } catch (error: Exception) {
            callback.error("FILE", error.message, null)
        } finally {
            saveBytes = null
        }
    }
}
