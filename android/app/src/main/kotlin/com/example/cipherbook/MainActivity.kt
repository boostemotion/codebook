package com.example.cipherbook

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executor
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private var quickUnlockStoreInProgress = false
    private var quickUnlockStoreGeneration = 0
    private var quickUnlockReadInProgress = false
    private var quickUnlockReadGeneration = 0
    private var activeQuickUnlockPrompt: BiometricPrompt? = null
    private var activeQuickUnlockStoreResult: MethodChannel.Result? = null
    private var activeQuickUnlockReadPrompt: BiometricPrompt? = null
    private var activeQuickUnlockReadResult: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private companion object {
        const val CHANNEL_NAME = "dev.codex.cipherbook/device_key_store"
        const val LAN_NETWORK_CHANNEL_NAME = "dev.codex.cipherbook/lan_network"
        const val LEGACY_KEY_ALIAS = "cipherbook_quick_unlock_key"
        const val KEY_ALIAS_A = "cipherbook_quick_unlock_key_a"
        const val KEY_ALIAS_B = "cipherbook_quick_unlock_key_b"
        const val CACHE_FILE_NAME = "quick_unlock.keystore"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
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
                "hasWrappedDekCache" -> result.success(hasValidQuickUnlockCache())
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAN_NETWORK_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
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

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) {
            return
        }
        val wifiManager = getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return
        multicastLock = wifiManager.createMulticastLock("cipherbook-lan-sync").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { lock ->
            if (lock.isHeld) {
                lock.release()
            }
        }
        multicastLock = null
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
        if (quickUnlockStoreInProgress || quickUnlockReadInProgress) {
            result.error("store_failed", "Another biometric operation is already in progress.", null)
            return
        }
        quickUnlockStoreInProgress = true
        val operationGeneration = ++quickUnlockStoreGeneration
        activeQuickUnlockStoreResult = result

        val previousAlias = readQuickUnlockCache()?.alias
        val stagingAlias = if (previousAlias == KEY_ALIAS_A) KEY_ALIAS_B else KEY_ALIAS_A
        clearStagingQuickUnlock(stagingAlias)
        val cipher = runCatching {
            Cipher.getInstance(CIPHER_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey(stagingAlias))
            }
        }.getOrElse {
            clearStagingQuickUnlock(stagingAlias)
            finishQuickUnlockStore(operationGeneration)
            result.error("store_failed", "Failed to initialize biometric cipher.", null)
            return
        }

        val prompt = runCatching {
            BiometricPrompt(
                this,
                mainExecutor(),
                object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (!finishQuickUnlockStore(operationGeneration)) {
                        return
                    }
                    clearStagingQuickUnlock(stagingAlias)
                    result.error("store_failed", "Biometric authentication canceled.", null)
                }

                override fun onAuthenticationFailed() {
                    // Keep prompt active; only terminal callbacks should return.
                }

                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    if (!isQuickUnlockStoreCurrent(operationGeneration)) {
                        return
                    }
                    val authCipher = authResult.cryptoObject?.cipher ?: cipher
                    var cacheActivated = false
                    runCatching {
                        val ciphertext = authCipher.doFinal(bytes)
                        val payload = QuickUnlockCacheCodec.encode(
                            QuickUnlockCache(
                                alias = stagingAlias,
                                iv = authCipher.iv,
                                ciphertext = ciphertext,
                            ),
                        )
                        val stagingFile = quickUnlockStagingFile()
                        stagingFile.writeText(payload, Charsets.UTF_8)
                        if (!QuickUnlockCacheCodec.isUsable(stagingFile.readText(Charsets.UTF_8), ::hasSecretKey)) {
                            throw IllegalStateException("Staged quick unlock cache is invalid.")
                        }
                        activateStagedQuickUnlockCache(stagingFile)
                        cacheActivated = true
                    }.onSuccess {
                        if (!finishQuickUnlockStore(operationGeneration)) {
                            return@onSuccess
                        }
                        if (previousAlias != null && previousAlias != stagingAlias) {
                            runCatching { deleteSecretKey(previousAlias) }
                        }
                        runCatching { deleteSecretKey(LEGACY_KEY_ALIAS) }
                        result.success(null)
                    }.onFailure {
                        if (!finishQuickUnlockStore(operationGeneration)) {
                            return@onFailure
                        }
                        if (!cacheActivated) {
                            clearStagingQuickUnlock(stagingAlias)
                        }
                        result.error("store_failed", "Failed to store quick unlock key.", null)
                    }
                }
            },
        )
        }.getOrElse {
            if (finishQuickUnlockStore(operationGeneration)) {
                clearStagingQuickUnlock(stagingAlias)
                result.error("store_failed", "Failed to prepare biometric authentication.", null)
            }
            return
        }

        activeQuickUnlockPrompt = prompt
        runCatching {
            prompt.authenticate(
                buildPromptInfo(
                    title = "开启快速解锁",
                    subtitle = "请验证指纹以保存快速解锁密钥",
                ),
                BiometricPrompt.CryptoObject(cipher),
            )
        }.onFailure {
            if (finishQuickUnlockStore(operationGeneration)) {
                clearStagingQuickUnlock(stagingAlias)
                result.error("store_failed", "Failed to start biometric authentication.", null)
            }
        }
    }

    private fun authenticateAndReadWrappedDek(
        result: MethodChannel.Result,
    ) {
        if (!isQuickUnlockSupported()) {
            result.success(null)
            return
        }
        if (quickUnlockStoreInProgress || quickUnlockReadInProgress) {
            result.error("read_failed", "Another biometric operation is already in progress.", null)
            return
        }
        val cache = readQuickUnlockCache() ?: run {
            result.success(null)
            return
        }
        val secretKey = getSecretKey(cache.alias) ?: run {
            result.success(null)
            return
        }
        val cipher = runCatching {
            Cipher.getInstance(CIPHER_TRANSFORMATION).apply {
                init(
                    Cipher.DECRYPT_MODE,
                    secretKey,
                    GCMParameterSpec(GCM_TAG_BITS, cache.iv),
                )
            }
        }.getOrNull() ?: run {
            result.success(null)
            return
        }

        quickUnlockReadInProgress = true
        val operationGeneration = ++quickUnlockReadGeneration
        activeQuickUnlockReadResult = result
        val prompt = runCatching {
            BiometricPrompt(
                this,
                mainExecutor(),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (finishQuickUnlockRead(operationGeneration)) {
                            result.success(null)
                        }
                    }

                    override fun onAuthenticationFailed() {
                        // Keep prompt active; only terminal callbacks should return.
                    }

                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                        if (!isQuickUnlockReadCurrent(operationGeneration)) {
                            return
                        }
                        val authCipher = authResult.cryptoObject?.cipher ?: cipher
                        val plaintext = runCatching {
                            authCipher.doFinal(cache.ciphertext)
                        }.getOrNull()
                        if (finishQuickUnlockRead(operationGeneration)) {
                            result.success(plaintext)
                        }
                    }
                },
            )
        }.getOrElse {
            if (finishQuickUnlockRead(operationGeneration)) {
                result.success(null)
            }
            return
        }

        activeQuickUnlockReadPrompt = prompt
        runCatching {
            prompt.authenticate(
                buildPromptInfo(
                    title = "快速解锁",
                    subtitle = "请验证指纹以解锁密码库",
                ),
                BiometricPrompt.CryptoObject(cipher),
            )
        }.onFailure {
            if (finishQuickUnlockRead(operationGeneration)) {
                result.success(null)
            }
        }
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

    private fun isQuickUnlockStoreCurrent(operationGeneration: Int): Boolean {
        return quickUnlockStoreInProgress &&
            quickUnlockStoreGeneration == operationGeneration
    }

    private fun finishQuickUnlockStore(operationGeneration: Int): Boolean {
        if (!isQuickUnlockStoreCurrent(operationGeneration)) {
            return false
        }
        quickUnlockStoreInProgress = false
        activeQuickUnlockPrompt = null
        activeQuickUnlockStoreResult = null
        return true
    }

    private fun isQuickUnlockReadCurrent(operationGeneration: Int): Boolean {
        return quickUnlockReadInProgress &&
            quickUnlockReadGeneration == operationGeneration
    }

    private fun finishQuickUnlockRead(operationGeneration: Int): Boolean {
        if (!isQuickUnlockReadCurrent(operationGeneration)) {
            return false
        }
        quickUnlockReadInProgress = false
        activeQuickUnlockReadPrompt = null
        activeQuickUnlockReadResult = null
        return true
    }

    private fun clearQuickUnlock() {
        val pendingStoreResult = activeQuickUnlockStoreResult
        val pendingReadResult = activeQuickUnlockReadResult
        quickUnlockStoreGeneration++
        quickUnlockStoreInProgress = false
        activeQuickUnlockPrompt?.cancelAuthentication()
        activeQuickUnlockPrompt = null
        activeQuickUnlockStoreResult = null
        quickUnlockReadGeneration++
        quickUnlockReadInProgress = false
        activeQuickUnlockReadPrompt?.cancelAuthentication()
        activeQuickUnlockReadPrompt = null
        activeQuickUnlockReadResult = null
        pendingStoreResult?.error("store_failed", "Quick unlock setup was canceled.", null)
        pendingReadResult?.success(null)
        quickUnlockFile().delete()
        quickUnlockStagingFile().delete()
        quickUnlockBackupFile().delete()
        deleteSecretKey(LEGACY_KEY_ALIAS)
        deleteSecretKey(KEY_ALIAS_A)
        deleteSecretKey(KEY_ALIAS_B)
    }

    private fun clearStagingQuickUnlock(alias: String) {
        quickUnlockStagingFile().delete()
        deleteSecretKey(alias)
    }

    private fun activateStagedQuickUnlockCache(stagingFile: File) {
        val activeFile = quickUnlockFile()
        if (!activeFile.exists()) {
            check(stagingFile.renameTo(activeFile)) {
                "Failed to activate quick unlock cache."
            }
            return
        }

        val backupFile = quickUnlockBackupFile()
        backupFile.delete()
        check(activeFile.renameTo(backupFile)) {
            "Failed to preserve the current quick unlock cache."
        }
        if (!stagingFile.renameTo(activeFile)) {
            check(backupFile.renameTo(activeFile)) {
                "Failed to restore the current quick unlock cache."
            }
            throw IllegalStateException("Failed to activate quick unlock cache.")
        }
        backupFile.delete()
    }

    private fun hasValidQuickUnlockCache(): Boolean {
        val cache = readQuickUnlockCache() ?: return false
        return hasSecretKey(cache.alias)
    }

    private fun readQuickUnlockCache(): QuickUnlockCache? {
        val activeFile = quickUnlockFile()
        readQuickUnlockCache(activeFile)?.let {
            return it
        }
        if (activeFile.exists()) {
            return null
        }

        val backupFile = quickUnlockBackupFile()
        val backupCache = readQuickUnlockCache(backupFile) ?: return null
        return if (backupFile.renameTo(activeFile)) backupCache else null
    }

    private fun readQuickUnlockCache(file: File): QuickUnlockCache? {
        if (!file.exists()) {
            return null
        }
        return runCatching {
            QuickUnlockCacheCodec.decode(file.readText(Charsets.UTF_8))
        }.getOrNull()
    }

    private fun deleteSecretKey(alias: String) {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
    }

    private fun hasSecretKey(alias: String): Boolean = runCatching {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.containsAlias(alias)
    }.getOrDefault(false)

    private fun getSecretKey(alias: String): SecretKey? = runCatching {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            .getKey(alias, null) as? SecretKey
    }.getOrNull()

    private fun quickUnlockFile(): File {
        return File(filesDir, CACHE_FILE_NAME)
    }

    private fun quickUnlockStagingFile(): File {
        return File(filesDir, "$CACHE_FILE_NAME.staging")
    }

    private fun quickUnlockBackupFile(): File {
        return File(filesDir, "$CACHE_FILE_NAME.previous")
    }

    private fun getOrCreateSecretKey(alias: String): SecretKey {
        getSecretKey(alias)?.let {
            return it
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val specBuilder = KeyGenParameterSpec.Builder(
            alias,
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
