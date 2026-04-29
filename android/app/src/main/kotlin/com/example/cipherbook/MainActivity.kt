package com.example.cipherbook

import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL_NAME = "dev.codex.cipherbook/device_key_store"
        const val KEY_ALIAS = "cipherbook_quick_unlock_key"
        const val CACHE_FILE_NAME = "quick_unlock.keystore"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
        const val CACHE_VERSION = 1
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isQuickUnlockSupported())
                "storeWrappedDek" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || bytes.isEmpty()) {
                        result.error(
                            "invalid_argument",
                            "Expected non-empty Uint8List.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    runCatching {
                        storeWrappedDek(bytes)
                    }.onSuccess {
                        result.success(null)
                    }.onFailure {
                        result.error("store_failed", "Failed to store quick unlock key.", null)
                    }
                }
                "readWrappedDek" -> {
                    runCatching {
                        readWrappedDek()
                    }.onSuccess {
                        result.success(it)
                    }.onFailure {
                        result.success(null)
                    }
                }
                "clear" -> {
                    clearQuickUnlock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    private fun preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        val display = windowManager.defaultDisplay
        val currentMode = display.mode
        val mode = display.supportedModes
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
            ?: return

        val attributes = window.attributes
        if (attributes.preferredDisplayModeId != mode.modeId) {
            attributes.preferredDisplayModeId = mode.modeId
            window.attributes = attributes
        }
    }

    private fun isQuickUnlockSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
    }

    private fun storeWrappedDek(bytes: ByteArray) {
        if (!isQuickUnlockSupported()) {
            throw IllegalStateException("Android Keystore is unavailable.")
        }

        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val ciphertext = cipher.doFinal(bytes)
        val payload = JSONObject()
            .put("version", CACHE_VERSION)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .toString()

        quickUnlockFile().writeText(payload, Charsets.UTF_8)
    }

    private fun readWrappedDek(): ByteArray? {
        if (!isQuickUnlockSupported()) {
            return null
        }
        val file = quickUnlockFile()
        if (!file.exists()) {
            return null
        }

        return runCatching {
            val payload = JSONObject(file.readText(Charsets.UTF_8))
            if (payload.optInt("version") != CACHE_VERSION) {
                return null
            }
            val iv = Base64.decode(payload.getString("iv"), Base64.NO_WRAP)
            val ciphertext = Base64.decode(payload.getString("ciphertext"), Base64.NO_WRAP)
            val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(),
                GCMParameterSpec(GCM_TAG_BITS, iv),
            )
            cipher.doFinal(ciphertext)
        }.getOrNull()
    }

    private fun clearQuickUnlock() {
        quickUnlockFile().delete()
    }

    private fun quickUnlockFile(): File {
        return File(filesDir, CACHE_FILE_NAME)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
            load(null)
        }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let {
            return it
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }
}
