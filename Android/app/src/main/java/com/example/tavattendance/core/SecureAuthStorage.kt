package com.example.tavattendance.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.github.jan.supabase.auth.CodeVerifierCache
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.user.UserSession
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private const val ANDROID_KEYSTORE = "AndroidKeyStore"
private const val KEY_ALIAS = "tava.supabase.auth.aes.v1"
private const val PREFS_NAME = "tava_secure_auth"
private const val SESSION_KEY = "session.v1"
private const val CODE_VERIFIER_KEY = "code_verifier.v1"
private const val PAYLOAD_VERSION: Byte = 1
private const val GCM_IV_BYTES = 12
private const val GCM_TAG_BITS = 128

/**
 * Reproduces supabase-kt's Settings key so existing plaintext sessions can be
 * migrated once and then removed from the default SharedPreferences file.
 */
internal fun legacySupabaseSettingsKey(supabaseUrl: String, suffix: String): String {
    val projectKey = supabaseUrl
        .removeSuffix("/")
        .replace('/', '-')
        .replace('.', '-')
    return "sb-$projectKey-$suffix"
}

/**
 * Small authenticated-encryption store for auth material. The AES key is
 * non-exportable in Android Keystore; SharedPreferences contains only a
 * versioned AES-GCM nonce + ciphertext. The preference name is supplied as
 * associated data so ciphertext cannot be swapped between entries.
 */
internal class KeystoreStringStore(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val mutex = Mutex()

    suspend fun put(key: String, value: String) = mutex.withLock {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        check(iv.size == GCM_IV_BYTES) { "Unexpected AES-GCM nonce size" }

        val payload = ByteArray(1 + iv.size + ciphertext.size)
        payload[0] = PAYLOAD_VERSION
        iv.copyInto(payload, destinationOffset = 1)
        ciphertext.copyInto(payload, destinationOffset = 1 + iv.size)
        check(preferences.edit().putString(key, Base64.encodeToString(payload, Base64.NO_WRAP)).commit()) {
            "Could not persist encrypted auth state"
        }
    }

    suspend fun get(key: String): String? = mutex.withLock {
        val encoded = preferences.getString(key, null) ?: return@withLock null
        try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            require(payload.size >= 1 + GCM_IV_BYTES + GCM_TAG_BITS / 8) {
                "Encrypted auth state is truncated"
            }
            require(payload[0] == PAYLOAD_VERSION) { "Unknown encrypted auth state version" }
            val iv = payload.copyOfRange(1, 1 + GCM_IV_BYTES)
            val ciphertext = payload.copyOfRange(1 + GCM_IV_BYTES, payload.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (error: Exception) {
            // Tampered, restored-without-its-key, or otherwise unreadable auth
            // state must never be retried as if it were a valid session.
            preferences.edit().remove(key).commit()
            throw IllegalStateException("Encrypted auth state could not be read", error)
        }
    }

    suspend fun remove(key: String) = mutex.withLock {
        check(preferences.edit().remove(key).commit()) {
            "Could not remove encrypted auth state"
        }
    }

    /**
     * Copies a legacy value only after encrypted write + read-back succeeds,
     * then synchronously removes the plaintext source. If encrypted state
     * already exists, any leftover legacy copy is scrubbed.
     */
    suspend fun migrate(
        legacyPreferencesName: String,
        legacyKey: String,
        secureKey: String,
    ) {
        val legacyPreferences =
            appContext.getSharedPreferences(legacyPreferencesName, Context.MODE_PRIVATE)
        val legacyValue = legacyPreferences.getString(legacyKey, null) ?: return
        val existing = get(secureKey)
        if (existing == null) {
            put(secureKey, legacyValue)
            check(get(secureKey) == legacyValue) { "Encrypted auth migration verification failed" }
        }
        check(legacyPreferences.edit().remove(legacyKey).commit()) {
            "Could not remove legacy plaintext auth state"
        }
    }

    private fun getOrCreateKey(): SecretKey = synchronized(KEY_LOCK) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey) ?: KeyGenerator
            .getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                        KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .setRandomizedEncryptionRequired(true)
                        .build()
                )
            }
            .generateKey()
    }

    private companion object {
        val KEY_LOCK = Any()
    }
}

internal class EncryptedSessionManager(
    context: Context,
    private val supabaseUrl: String,
    private val store: KeystoreStringStore,
) : SessionManager {
    private val preferencesName = "${context.packageName}_preferences"
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }
    private val migrationMutex = Mutex()
    private var migrationComplete = false

    private suspend fun migrateLegacySession() {
        migrationMutex.withLock {
            if (migrationComplete) return@withLock
            store.migrate(
                legacyPreferencesName = preferencesName,
                legacyKey = legacySupabaseSettingsKey(supabaseUrl, "session"),
                secureKey = SESSION_KEY,
            )
            migrationComplete = true
        }
    }

    override suspend fun saveSession(session: UserSession) {
        migrateLegacySession()
        store.put(SESSION_KEY, json.encodeToString(session))
    }

    override suspend fun loadSession(): UserSession {
        migrateLegacySession()
        val encoded = store.get(SESSION_KEY) ?: error("No encrypted session stored")
        return try {
            json.decodeFromString<UserSession>(encoded)
        } catch (error: Exception) {
            store.remove(SESSION_KEY)
            throw IllegalStateException("Encrypted session is invalid", error)
        }
    }

    override suspend fun deleteSession() {
        migrateLegacySession()
        store.remove(SESSION_KEY)
    }
}

internal class EncryptedCodeVerifierCache(
    context: Context,
    private val supabaseUrl: String,
    private val store: KeystoreStringStore,
) : CodeVerifierCache {
    private val preferencesName = "${context.packageName}_preferences"
    private val migrationMutex = Mutex()
    private var migrationComplete = false

    private suspend fun migrateLegacyVerifier() {
        migrationMutex.withLock {
            if (migrationComplete) return@withLock
            store.migrate(
                legacyPreferencesName = preferencesName,
                legacyKey = legacySupabaseSettingsKey(supabaseUrl, "supabase_code_verifier"),
                secureKey = CODE_VERIFIER_KEY,
            )
            migrationComplete = true
        }
    }

    override suspend fun saveCodeVerifier(codeVerifier: String) {
        migrateLegacyVerifier()
        store.put(CODE_VERIFIER_KEY, codeVerifier)
    }

    override suspend fun loadCodeVerifier(): String? {
        migrateLegacyVerifier()
        return store.get(CODE_VERIFIER_KEY)
    }

    override suspend fun deleteCodeVerifier() {
        migrateLegacyVerifier()
        store.remove(CODE_VERIFIER_KEY)
    }
}
