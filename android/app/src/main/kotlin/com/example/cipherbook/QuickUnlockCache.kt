package com.example.cipherbook

import android.util.Base64
import org.json.JSONObject

internal data class QuickUnlockCache(
    val alias: String,
    val iv: ByteArray,
    val ciphertext: ByteArray,
)

internal object QuickUnlockCacheCodec {
    const val version = 3
    private const val gcmIvBytes = 12
    private const val gcmAuthenticationTagBytes = 16

    fun encode(
        cache: QuickUnlockCache,
        encodeBase64: (ByteArray) -> String = {
            Base64.encodeToString(it, Base64.NO_WRAP)
        },
    ): String = JSONObject()
        .put("version", version)
        .put("alias", cache.alias)
        .put("iv", encodeBase64(cache.iv))
        .put("ciphertext", encodeBase64(cache.ciphertext))
        .toString()

    fun decode(
        payload: String,
        decodeBase64: (String) -> ByteArray? = { value ->
            runCatching { Base64.decode(value, Base64.NO_WRAP) }.getOrNull()
        },
    ): QuickUnlockCache? = runCatching {
        val json = JSONObject(payload)
        if (json.optInt("version") != version) {
            return null
        }
        val alias = json.optString("alias")
        val iv = decodeBase64(json.optString("iv"))
        val ciphertext = decodeBase64(json.optString("ciphertext"))
        if (
            alias.isBlank() ||
            iv == null ||
            iv.size != gcmIvBytes ||
            ciphertext == null ||
            ciphertext.size <= gcmAuthenticationTagBytes
        ) {
            return null
        }
        QuickUnlockCache(alias, iv, ciphertext)
    }.getOrNull()

    fun isUsable(
        payload: String,
        keyExists: (String) -> Boolean,
        decodeBase64: (String) -> ByteArray? = { value ->
            runCatching { Base64.decode(value, Base64.NO_WRAP) }.getOrNull()
        },
    ): Boolean = decode(payload, decodeBase64)?.let { keyExists(it.alias) } == true
}
