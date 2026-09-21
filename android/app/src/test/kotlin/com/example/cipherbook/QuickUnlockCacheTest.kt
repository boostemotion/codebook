package com.example.cipherbook

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class QuickUnlockCacheTest {
    private val encodeBase64 = { bytes: ByteArray ->
        Base64.getEncoder().encodeToString(bytes)
    }
    private val decodeBase64 = { value: String ->
        runCatching { Base64.getDecoder().decode(value) }.getOrNull()
    }

    @Test
    fun `decodes a complete cache for an available alias`() {
        val payload = QuickUnlockCacheCodec.encode(
            QuickUnlockCache(
                alias = "cipherbook_quick_unlock_key_a",
                iv = ByteArray(12) { it.toByte() },
                ciphertext = ByteArray(17) { (it + 1).toByte() },
            ),
            encodeBase64,
        )

        val cache = QuickUnlockCacheCodec.decode(payload, decodeBase64)

        assertNotNull(cache)
        assertTrue(
            QuickUnlockCacheCodec.isUsable(
                payload,
                { it == cache!!.alias },
                decodeBase64,
            ),
        )
    }

    @Test
    fun `rejects malformed or incomplete cache payloads`() {
        val valid = QuickUnlockCacheCodec.encode(
            QuickUnlockCache(
                alias = "cipherbook_quick_unlock_key_a",
                iv = ByteArray(12),
                ciphertext = ByteArray(17),
            ),
            encodeBase64,
        )

        assertFalse(QuickUnlockCacheCodec.isUsable("not json", { true }, decodeBase64))
        assertFalse(
            QuickUnlockCacheCodec.isUsable(
                valid.replace("\"version\":3", "\"version\":999"),
                { true },
                decodeBase64,
            ),
        )
        assertFalse(
            QuickUnlockCacheCodec.isUsable(
                valid.replace("\"alias\":\"cipherbook_quick_unlock_key_a\",", ""),
                { true },
                decodeBase64,
            ),
        )
        assertFalse(
            QuickUnlockCacheCodec.isUsable(
                valid.replace("\"iv\":\"AAAAAAAAAAAAAAAA\"", "\"iv\":\"invalid\""),
                { true },
                decodeBase64,
            ),
        )
        assertFalse(
            QuickUnlockCacheCodec.isUsable(
                valid.replace(
                    "\"ciphertext\":\"AAAAAAAAAAAAAAAAAAAAAAA=\"",
                    "\"ciphertext\":\"\"",
                ),
                { true },
                decodeBase64,
            ),
        )
        assertFalse(QuickUnlockCacheCodec.isUsable(valid, { false }, decodeBase64))
    }

    @Test
    fun `requires a twelve byte iv and ciphertext containing authentication tag`() {
        val invalidIv = QuickUnlockCacheCodec.encode(
            QuickUnlockCache(
                alias = "cipherbook_quick_unlock_key_a",
                iv = ByteArray(11),
                ciphertext = ByteArray(17),
            ),
            encodeBase64,
        )
        val shortCiphertext = QuickUnlockCacheCodec.encode(
            QuickUnlockCache(
                alias = "cipherbook_quick_unlock_key_a",
                iv = ByteArray(12),
                ciphertext = ByteArray(16),
            ),
            encodeBase64,
        )

        assertNull(QuickUnlockCacheCodec.decode(invalidIv, decodeBase64))
        assertNull(QuickUnlockCacheCodec.decode(shortCiphertext, decodeBase64))
    }
}
