package com.example.tavattendance

import com.example.tavattendance.screens.kiosk.KioskAction
import com.example.tavattendance.screens.kiosk.KioskLockoutState
import com.example.tavattendance.screens.kiosk.KioskUnlockResult
import com.example.tavattendance.screens.kiosk.StoredKioskPinDisposition
import com.example.tavattendance.screens.kiosk.hashPinLegacy
import com.example.tavattendance.screens.kiosk.hashPinPbkdf2
import com.example.tavattendance.screens.kiosk.isKioskActionAuthorized
import com.example.tavattendance.screens.kiosk.isKioskUnlockBlocked
import com.example.tavattendance.screens.kiosk.secureEquals
import com.example.tavattendance.screens.kiosk.shouldLockKioskOnStart
import com.example.tavattendance.screens.kiosk.storedKioskPinDisposition
import com.example.tavattendance.screens.kiosk.transitionKioskUnlockState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KioskSecurityTest {
    @Test
    fun configuredPinAlwaysStartsLocked() {
        assertTrue(shouldLockKioskOnStart("v2:hash"))
        assertTrue(shouldLockKioskOnStart("legacy-pin"))
        assertFalse(shouldLockKioskOnStart(""))
    }

    @Test
    fun lockedKioskOnlyAllowsStudentSignIn() {
        assertTrue(isKioskActionAuthorized(KioskAction.SignIn, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.MarkPresent, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.MarkLate, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.MarkAbsentInformed, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.MarkAbsentNoNotice, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.Clear, isAdminMode = false))
    }

    @Test
    fun unlockedAdminCanRunAllKioskActions() {
        KioskAction.entries.forEach { action ->
            assertTrue(isKioskActionAuthorized(action, isAdminMode = true))
        }
    }

    @Test
    fun activeLockoutRejectsEvenACorrectPinWithoutChangingState() {
        val state = KioskLockoutState(
            failedAttempts = 0,
            lockoutStage = 1,
            lockedUntilMillis = 40_000L,
        )

        val (nextState, result) = transitionKioskUnlockState(
            currentState = state,
            pinMatches = true,
            nowMillis = 10_000L,
        )

        assertTrue(isKioskUnlockBlocked(state, nowMillis = 10_000L))
        assertEquals(state, nextState)
        assertEquals(KioskUnlockResult.LockedOut(40_000L), result)
    }

    @Test
    fun fiveRapidFailuresAtomicallyEnterFirstLockoutWindow() {
        val attemptTime = 10_000L
        var state = KioskLockoutState()
        var result: KioskUnlockResult = KioskUnlockResult.Unlocked

        repeat(5) {
            val transition = transitionKioskUnlockState(
                currentState = state,
                pinMatches = false,
                nowMillis = attemptTime,
            )
            state = transition.first
            result = transition.second
        }

        assertEquals(KioskLockoutState(0, 1, 40_000L), state)
        assertEquals(KioskUnlockResult.LockedOut(40_000L), result)
    }

    @Test
    fun incorrectPinResultReportsPostAttemptCounter() {
        val (state, result) = transitionKioskUnlockState(
            currentState = KioskLockoutState(),
            pinMatches = false,
            nowMillis = 10_000L,
        )

        assertEquals(KioskLockoutState(1, 0, 0L), state)
        assertEquals(KioskUnlockResult.IncorrectPin(attemptsRemaining = 4), result)
    }

    @Test
    fun successfulPinAfterExpiryClearsEscalationState() {
        val (state, result) = transitionKioskUnlockState(
            currentState = KioskLockoutState(
                failedAttempts = 0,
                lockoutStage = 3,
                lockedUntilMillis = 9_999L,
            ),
            pinMatches = true,
            nowMillis = 10_000L,
        )

        assertEquals(KioskLockoutState(), state)
        assertEquals(KioskUnlockResult.Unlocked, result)
    }

    @Test
    fun secondLockoutStageDoublesWindow() {
        val afterFirst = KioskLockoutState(failedAttempts = 0, lockoutStage = 1, lockedUntilMillis = 0L)
        val now = 50_000L
        var state = afterFirst
        var result: KioskUnlockResult = KioskUnlockResult.Unlocked
        repeat(5) {
            val transition = transitionKioskUnlockState(state, pinMatches = false, nowMillis = now)
            state = transition.first
            result = transition.second
        }
        assertEquals(KioskLockoutState(0, 2, now + 60_000L), state)
        assertEquals(KioskUnlockResult.LockedOut(now + 60_000L), result)
    }

    @Test
    fun classifiesLegacyPlaintextCurrentAndMalformedPins() {
        assertEquals(StoredKioskPinDisposition.None, storedKioskPinDisposition(""))
        assertEquals(StoredKioskPinDisposition.LegacyPlaintext, storedKioskPinDisposition("1234"))
        assertEquals(
            StoredKioskPinDisposition.CurrentHash,
            storedKioskPinDisposition("v2:" + "a".repeat(64)),
        )
        assertEquals(
            StoredKioskPinDisposition.LegacyHash,
            storedKioskPinDisposition("v1:" + "b".repeat(64)),
        )
        assertEquals(
            StoredKioskPinDisposition.Malformed,
            storedKioskPinDisposition("v2:not-a-hash"),
        )
    }

    @Test
    fun currentHashRecognitionIsStableAndConstantTimeCompareWorks() {
        val salt = "device-salt"
        val hash = hashPinPbkdf2("1234", salt)
        assertTrue(hash.startsWith("v2:"))
        assertEquals(67, hash.length)
        assertTrue(secureEquals(hash, hashPinPbkdf2("1234", salt)))
        assertFalse(secureEquals(hash, hashPinPbkdf2("9999", salt)))
        val legacy = hashPinLegacy("1234", salt)
        assertTrue(legacy.startsWith("v1:"))
        assertFalse(secureEquals(hash, legacy))
    }

    @Test
    fun qrSignInUsesSameStudentIdResolverAsCardLookup() {
        // Characterization: QR path and card path both resolve student UUIDs via
        // AttendanceService.studentIdFromQrPayload before calling performSignIn.
        // Payload parsing coverage lives in QrPayloadTest; this documents the shared entry.
        val id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        assertEquals(id, com.example.tavattendance.data.service.AttendanceService.studentIdFromQrPayload(id))
    }
}
