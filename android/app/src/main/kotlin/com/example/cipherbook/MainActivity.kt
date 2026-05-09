package com.example.cipherbook

import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executor
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL_NAME = "dev.codex.cipherbook/device_key_store"
        const val KEY_ALIAS = "cipherbook_quick_unlock_key"
        const val CACHE_FILE_NAME = "quick_unlock.keystore"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
        const val CACHE_VERSION = 2
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
                    authenticateAndStoreWrappedDek(bytes, result)
                }
                "readWrappedDek" -> authenticateAndReadWrappedDek(result)
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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return false
        }
        val manager = BiometricManager.from(this)
        val canAuthenticate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            manager.canAuthenticate()
        }
        return canAuthenticate == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun authenticateAndStoreWrappedDek(
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (!isQuickUnlockSupported()) {
            result.error("store_failed", "Biometric auth is unavailable.", null)
            return
        }

        // Rotate keystore alias so upgraded builds don't reuse non-biometric keys.
        deleteSecretKey()

        val cipher = runCatching {
            Cipher.getInstance(CIPHER_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            }
        }.getOrElse {
            result.error("store_failed", "Failed to initialize biometric cipher.", null)
            return
        }

        val prompt = BiometricPrompt(
            this,
            mainExecutor(),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    result.error("store_failed", "Biometric authentication canceled.", null)
                }

                override fun onAuthenticationFailed() {
                    // Keep prompt active; only terminal callbacks should return.
                }

                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    val authCipher = authResult.cryptoObject?.cipher ?: cipher
                    runCatching {
                        val ciphertext = authCipher.doFinal(bytes)
                        val payload = JSONObject()
                            .put("version", CACHE_VERSION)
                            .put("iv", Base64.encodeToString(authCipher.iv, Base64.NO_WRAP))
                            .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                            .toString()
                        quickUnlockFile().writeText(payload, Charsets.UTF_8)
                    }.onSuccess {
                        result.success(null)
                    }.onFailure {
                        result.error("store_failed", "Failed to store quick unlock key.", null)
                    }
                }
            },
        )

        prompt.authenticate(
            buildPromptInfo(
                title = "开启快速解锁",
                subtitle = "请验证指纹以保存快速解锁密钥",
            ),
            BiometricPrompt.CryptoObject(cipher),
        )
    }

    private fun authenticateAndReadWrappedDek(
        result: MethodChannel.Result,
    ) {
        if (!isQuickUnlockSupported()) {
            result.success(null)
            return
        }
        val file = quickUnlockFile()
        if (!file.exists()) {
            result.success(null)
            return
        }

        val payload = runCatching {
            JSONObject(file.readText(Charsets.UTF_8))
        }.getOrNull() ?: run {
            result.success(null)
            return
        }

        if (payload.optInt("version") != CACHE_VERSION) {
            result.success(null)
            return
        }

        val iv = runCatching {
            Base64.decode(payload.getString("iv"), Base64.NO_WRAP)
        }.getOrNull() ?: run {
            result.success(null)
            return
        }
        val ciphertext = runCatching {
            Base64.decode(payload.getString("ciphertext"), Base64.NO_WRAP)
        }.getOrNull() ?: run {
            result.success(null)
            return
        }

        val cipher = runCatching {
            Cipher.getInstance(CIPHER_TRANSFORMATION).apply {
                init(
                    Cipher.DECRYPT_MODE,
                    getOrCreateSecretKey(),
                    GCMParameterSpec(GCM_TAG_BITS, iv),
                )
            }
        }.getOrNull() ?: run {
            result.success(null)
            return
        }

        val prompt = BiometricPrompt(
            this,
            mainExecutor(),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    result.success(null)
                }

                override fun onAuthenticationFailed() {
                    // Keep prompt active; only terminal callbacks should return.
                }

                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    val authCipher = authResult.cryptoObject?.cipher ?: cipher
                    val plaintext = runCatching {
                        authCipher.doFinal(ciphertext)
                    }.getOrNull()
                    result.success(plaintext)
                }
            },
        )

        prompt.authenticate(
            buildPromptInfo(
                title = "快速解锁",
                subtitle = "请验证指纹以解锁密码库",
            ),
            BiometricPrompt.CryptoObject(cipher),
        )
    }

    private fun buildPromptInfo(title: String, subtitle: String): BiometricPrompt.PromptInfo {
        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText("取消")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            promptInfoBuilder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        }
        return promptInfoBuilder.build()
    }

    private fun clearQuickUnlock() {
        quickUnlockFile().delete()
        deleteSecretKey()
    }

    private fun deleteSecretKey() {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
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
        val specBuilder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            specBuilder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            specBuilder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            specBuilder.setInvalidatedByBiometricEnrollment(true)
        }

        keyGenerator.init(specBuilder.build())
        return keyGenerator.generateKey()
    }

    private fun mainExecutor(): Executor {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            super.getMainExecutor()
        } else {
            Executor { command -> runOnUiThread(command) }
        }
    }
}
