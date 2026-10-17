package com.example.leo_desk

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "leo_desk/database_export"
    private val createDocumentRequest = 9301
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportFile: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveDatabaseFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (pendingExportResult != null) {
                result.error("export_in_progress", "A database export is already in progress.", null)
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            val fileName = call.argument<String>("fileName")
            if (path.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error("invalid_arguments", "A database path and filename are required.", null)
                return@setMethodCallHandler
            }

            val file = File(path)
            if (!file.isFile) {
                result.error("backup_missing", "The temporary database backup could not be found.", null)
                return@setMethodCallHandler
            }

            pendingExportResult = result
            pendingExportFile = file
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                startActivityForResult(intent, createDocumentRequest)
            } catch (error: Exception) {
                pendingExportResult = null
                pendingExportFile = null
                result.error("file_picker_failed", error.message, null)
            }
        }
    }

    @Deprecated("Deprecated in Android, retained for broad device compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createDocumentRequest) return

        val methodResult = pendingExportResult
        val sourceFile = pendingExportFile
        pendingExportResult = null
        pendingExportFile = null

        if (methodResult == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            methodResult.success(false)
            return
        }
        if (sourceFile == null) {
            methodResult.error("backup_missing", "The temporary database backup is unavailable.", null)
            return
        }

        try {
            val destination: Uri = data.data!!
            contentResolver.openOutputStream(destination, "w").use { output ->
                if (output == null) {
                    throw IllegalStateException("Could not open the selected destination.")
                }
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            methodResult.success(true)
        } catch (error: Exception) {
            methodResult.error("export_write_failed", error.message, null)
        }
    }
}
