package org.spectrum3847.spectrumstrategy

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val APK_INSTALLER_CHANNEL = "org.spectrum3847.spectrumstrategy/apk_installer"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APK_INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrEmpty()) {
                result.error("bad_args", "No APK path given", null)
                return@setMethodCallHandler
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {

                    startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        },
                    )
                    result.success("permission_required")
                    return@setMethodCallHandler
                }
                installApk(path)
                result.success(true)
            } catch (error: ActivityNotFoundException) {
                result.error("no_installer", "No package installer activity found", null)
            } catch (error: IllegalArgumentException) {

                result.error("bad_path", error.message, null)
            }
        }
    }

    private fun installApk(path: String) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            File(path),
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
