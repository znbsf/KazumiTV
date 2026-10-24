package com.example.kazumi

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile

/** No exported commands or QA bypass: only the installed formal identity updates. */
class TvUpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.znbsf.kazumi/update")
    private val officialPackage = "com.znbsf.kazumi.fluttertv"
    private val officialCertificate = "3225e3b8676eed2d2f28fad6255881120f6335ade615bbb27673d974727ce806"
    @Suppress("DEPRECATION")
    private val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "identity" -> {
                        val installed = installed()
                        result.success(mapOf("package" to installed.packageName,
                            "certificate" to certificate(installed),
                            "debuggable" to ((installed.applicationInfo!!.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
                            "abis" to Build.SUPPORTED_ABIS.toList()))
                    }
                    "permissionSettings" -> {
                        requireFormalIdentity()
                        if (Build.VERSION.SDK_INT >= 26) activity.startActivity(Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                        result.success(null)
                    }
                    "validate", "install" -> {
                        // APK hashing and ZIP inspection must not block remote-control input.
                        Thread {
                            val checked = runCatching { validate(call) }
                            activity.runOnUiThread {
                                try {
                                    val file = checked.getOrThrow()
                                    if (call.method == "validate") result.success(null)
                                    else if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                        result.success("permission_required")
                                    } else {
                                        val uri = FileProvider.getUriForFile(activity,
                                            "${activity.packageName}.updates", file)
                                        activity.startActivity(Intent(Intent.ACTION_VIEW)
                                            .setDataAndType(uri, "application/vnd.android.package-archive")
                                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                        result.success("installer_opened")
                                    }
                                } catch (e: Exception) {
                                    result.error("UPDATE_REJECTED", e.message ?: "无法启动安装", null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("UPDATE_REJECTED", e.message ?: "无法读取更新身份", null)
            }
        }
    }

    fun detach() = channel.setMethodCallHandler(null)

    @Suppress("DEPRECATION")
    private fun installed() = activity.packageManager.getPackageInfo(activity.packageName, flags)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun certificate(info: PackageInfo): String {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        require(signatures?.size == 1) { "安装包签名信息无效" }
        return hex(MessageDigest.getInstance("SHA-256").digest(signatures!![0].toByteArray()))
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun requireFormalIdentity(): PackageInfo {
        val info = installed()
        require(info.packageName == officialPackage && certificate(info) == officialCertificate &&
            (info.applicationInfo!!.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) { "此安装包不参与正式版升级" }
        return info
    }

    private fun validate(call: MethodCall): File {
        val current = requireFormalIdentity()
        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
        val cache = activity.cacheDir.canonicalFile
        require(file.parentFile == cache && file.isFile && file.extension == "apk") { "更新文件位置无效" }
        val size = call.argument<Number>("size")?.toLong() ?: 0L
        require(size in 1..536870912L && file.length() == size) { "安装包大小不一致" }
        val hash = call.argument<String>("sha256") ?: ""
        require(Regex("[a-f0-9]{64}").matches(hash)) { "缺少安装包校验值" }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        require(hex(digest.digest()) == hash) { "文件完整性验证失败" }
        // Android 9 archive parsing may collect certificates only with GET_SIGNATURES.
        // Request both fields; still require one current signer and the pinned certificate.
        val target = activity.packageManager.getPackageArchiveInfo(
            file.path, flags or PackageManager.GET_SIGNATURES)
            ?: throw IllegalArgumentException("无法读取安装包")
        require(target.packageName == officialPackage && certificate(target) == officialCertificate &&
            (target.applicationInfo!!.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) { "安装包身份或签名不匹配" }
        val version = call.argument<String>("version") ?: ""
        require(Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matches(version) &&
            target.versionName == version && versionCode(target) > versionCode(current)) { "安装包版本不匹配或不是新版本" }
        require(Build.VERSION.SDK_INT >= (target.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE)) { "电视系统版本过低" }
        val abi = call.argument<String>("abi") ?: ""
        require(abi in Build.SUPPORTED_ABIS && abi in listOf("armeabi-v7a", "arm64-v8a", "x86_64")) { "安装包架构不支持" }
        ZipFile(file).use { zip ->
            val nativeAbis = zip.entries().asSequence().map { it.name }
                .filter { it.startsWith("lib/") && it.endsWith(".so") }
                .map { it.split('/')[1] }.toSet()
            require(nativeAbis == setOf(abi) && zip.getEntry("lib/$abi/libflutter.so") != null) { "安装包架构不匹配" }
        }
        return file
    }
}
