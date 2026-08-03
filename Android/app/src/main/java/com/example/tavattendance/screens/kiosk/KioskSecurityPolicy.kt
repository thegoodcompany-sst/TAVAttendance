package com.example.tavattendance.screens.kiosk

import java.security.MessageDigest
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

// ---------------------------------------------------------------------------
// PIN hashing helpers
// ---------------------------------------------------------------------------

/**
 * Hash a PIN using PBKDF2-SHA256 with 10,000 iterations and the device salt.
 * Output format: "v2:<64 hex chars>" (32-byte / 256-bit derived key).
 *
 * Matches iOS: CCKeyDerivationPBKDF / kCCPBKDF2 / kCCPRFHmacAlgSHA256 /
 *   10_000 iterations / 32-byte output / "v1:" prefix (iOS calls it v1 for
 *   its PBKDF2; Android uses "v2:" to distinguish from the old SHA-256 "v1:").
 *
 * NOTE: iOS writes "v1:" for PBKDF2 hashes. Android previously wrote "v1:" for
 * plain-SHA-256 hashes. To avoid a collision the Android PBKDF2 format uses
 * "v2:" so migration code can tell them apart.
 */
internal fun hashPinPbkdf2(pin: String, salt: String): String {
    val saltBytes = salt.toByteArray(Charsets.UTF_8)
    val spec = PBEKeySpec(pin.toCharArray(), saltBytes, 10_000, 256)
    val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
    val derived = factory.generateSecret(spec).encoded
    spec.clearPassword()
    return "v2:" + derived.joinToString("") { "%02x".format(it) }
}

/**
 * Legacy hash: single-round SHA-256 over "$pin:$salt" (the original Android
 * implementation). Stored with prefix "v1:".
 */
internal fun hashPinLegacy(pin: String, salt: String): String {
    val md = MessageDigest.getInstance("SHA-256")
    val digest = md.digest("$pin:$salt".toByteArray(Charsets.UTF_8))
    return "v1:" + digest.joinToString("") { "%02x".format(it) }
}

/**
 * Constant-time comparison for hash strings.
 */
internal fun secureEquals(a: String, b: String): Boolean =
    MessageDigest.isEqual(a.toByteArray(Charsets.UTF_8), b.toByteArray(Charsets.UTF_8))

/** Shared across ViewModel instances so a second caller cannot race persisted PIN state. */
internal val kioskPinAttemptLock = Any()

enum class KioskAction { SignIn, MarkPresent, MarkLate, MarkAbsent, Clear }

/** Pure policy helpers kept separate from Compose so the security boundary is unit-testable. */
internal fun shouldLockKioskOnStart(storedPin: String): Boolean = storedPin.isNotEmpty()

internal fun isKioskActionAuthorized(action: KioskAction, isAdminMode: Boolean): Boolean =
    action == KioskAction.SignIn || isAdminMode

private const val KIOSK_ATTEMPTS_PER_STAGE = 5
private const val KIOSK_INITIAL_LOCKOUT_MILLIS = 30_000L
private const val KIOSK_MAX_LOCKOUT_MILLIS = 30 * 60_000L

internal data class KioskLockoutState(
    val failedAttempts: Int = 0,
    val lockoutStage: Int = 0,
    val lockedUntilMillis: Long = 0L,
)

internal sealed interface KioskUnlockResult {
    data object Unlocked : KioskUnlockResult
    data class IncorrectPin(val attemptsRemaining: Int) : KioskUnlockResult
    data class LockedOut(val lockedUntilMillis: Long) : KioskUnlockResult
    data object NotConfigured : KioskUnlockResult
}

internal fun isKioskUnlockBlocked(state: KioskLockoutState, nowMillis: Long): Boolean =
    nowMillis < state.lockedUntilMillis

/**
 * Pure lockout state machine used by the ViewModel and unit tests. A live
 * lockout wins even when the supplied PIN matches. Each fifth failure doubles
 * the lockout window (30s, 60s, 120s, ...), capped at 30 minutes; only a
 * successful PIN resets the stage.
 */
internal fun transitionKioskUnlockState(
    currentState: KioskLockoutState,
    pinMatches: Boolean,
    nowMillis: Long,
): Pair<KioskLockoutState, KioskUnlockResult> {
    if (isKioskUnlockBlocked(currentState, nowMillis)) {
        return currentState to KioskUnlockResult.LockedOut(currentState.lockedUntilMillis)
    }
    if (pinMatches) {
        return KioskLockoutState() to KioskUnlockResult.Unlocked
    }

    val attempts = currentState.failedAttempts.coerceIn(0, KIOSK_ATTEMPTS_PER_STAGE - 1) + 1
    if (attempts < KIOSK_ATTEMPTS_PER_STAGE) {
        val nextState = currentState.copy(
            failedAttempts = attempts,
            lockoutStage = currentState.lockoutStage.coerceAtLeast(0),
            lockedUntilMillis = 0L,
        )
        return nextState to KioskUnlockResult.IncorrectPin(
            attemptsRemaining = KIOSK_ATTEMPTS_PER_STAGE - attempts,
        )
    }

    val nextStage = (currentState.lockoutStage.coerceIn(0, 7) + 1).coerceAtMost(7)
    val exponent = (nextStage - 1).coerceIn(0, 6)
    val windowMillis =
        (KIOSK_INITIAL_LOCKOUT_MILLIS shl exponent).coerceAtMost(KIOSK_MAX_LOCKOUT_MILLIS)
    val lockedUntilMillis =
        if (nowMillis > Long.MAX_VALUE - windowMillis) Long.MAX_VALUE else nowMillis + windowMillis
    val nextState = KioskLockoutState(
        failedAttempts = 0,
        lockoutStage = nextStage,
        lockedUntilMillis = lockedUntilMillis,
    )
    return nextState to KioskUnlockResult.LockedOut(lockedUntilMillis)
}

/** Classify stored PIN representation for migration / fail-closed recovery. */
internal enum class StoredKioskPinDisposition {
    None, CurrentHash, LegacyHash, LegacyPlaintext, Malformed
}

internal fun storedKioskPinDisposition(storedPin: String): StoredKioskPinDisposition {
    if (storedPin.isEmpty()) return StoredKioskPinDisposition.None
    if (storedPin.startsWith("v2:") && storedPin.length == 67 &&
        storedPin.drop(3).all { it in "0123456789abcdefABCDEF" }
    ) {
        return StoredKioskPinDisposition.CurrentHash
    }
    if (storedPin.startsWith("v1:") && storedPin.length == 67 &&
        storedPin.drop(3).all { it in "0123456789abcdefABCDEF" }
    ) {
        return StoredKioskPinDisposition.LegacyHash
    }
    if (storedPin.length == 4 && storedPin.all { it.isDigit() }) {
        return StoredKioskPinDisposition.LegacyPlaintext
    }
    // Unrecognised prefixes still go through tryUnlock's prefix branches when length
    // looks hash-like; bare non-digit strings are treated as legacy plaintext compare.
    if (!storedPin.startsWith("v1:") && !storedPin.startsWith("v2:")) {
        return StoredKioskPinDisposition.LegacyPlaintext
    }
    return StoredKioskPinDisposition.Malformed
}
