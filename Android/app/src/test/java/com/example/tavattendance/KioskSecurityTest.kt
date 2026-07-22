package com.example.tavattendance

import com.example.tavattendance.screens.kiosk.KioskAction
import com.example.tavattendance.screens.kiosk.isKioskActionAuthorized
import com.example.tavattendance.screens.kiosk.shouldLockKioskOnStart
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
        assertFalse(isKioskActionAuthorized(KioskAction.MarkAbsent, isAdminMode = false))
        assertFalse(isKioskActionAuthorized(KioskAction.MarkNotHere, isAdminMode = false))
    }

    @Test
    fun unlockedAdminCanRunAllKioskActions() {
        KioskAction.entries.forEach { action ->
            assertTrue(isKioskActionAuthorized(action, isAdminMode = true))
        }
    }
}
