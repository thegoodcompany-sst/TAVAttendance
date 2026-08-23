package com.example.tavattendance

import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskEntry
import com.example.tavattendance.screens.kiosk.KIOSK_OFFLINE_BANNER
import com.example.tavattendance.screens.kiosk.KIOSK_SILENT_REFRESH_MS
import com.example.tavattendance.screens.kiosk.KIOSK_UNLOCK_CONTENT_DESCRIPTION
import com.example.tavattendance.screens.kiosk.KIOSK_UNLOCK_LONG_PRESS_MS
import com.example.tavattendance.screens.kiosk.KioskRosterPresentation
import com.example.tavattendance.screens.kiosk.kioskRosterPresentation
import com.example.tavattendance.screens.kiosk.mergeKioskEntriesPreservingPending
import com.example.tavattendance.screens.kiosk.shouldKeepLocalPendingEntry
import com.example.tavattendance.screens.kiosk.shouldSetKioskLoadingIndicator
import com.example.tavattendance.screens.kiosk.shouldShowKioskLoadingSpinner
import com.example.tavattendance.screens.kiosk.shouldSkipKioskSilentRefresh
import com.example.tavattendance.screens.kiosk.shouldSurfaceKioskLoadError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class KioskLoadPolicyTest {
    private fun entry(id: String, status: AttendanceStatus? = null) = KioskEntry(
        studentId = id,
        fullName = id,
        status = status,
        sessions = emptyList(),
    )

    @Test
    fun firstLoadShowsFullScreenLoader() {
        assertTrue(
            shouldShowKioskLoadingSpinner(
                isLoadInFlight = true,
                hasEntries = false,
                hasLoadedSuccessfully = false,
            )
        )
        assertTrue(shouldSetKioskLoadingIndicator(hasEntries = false, hasLoadedSuccessfully = false))
    }

    @Test
    fun subsequentRefreshDoesNotShowFullScreenLoader() {
        assertFalse(
            shouldShowKioskLoadingSpinner(
                isLoadInFlight = true,
                hasEntries = true,
                hasLoadedSuccessfully = true,
            )
        )
        assertFalse(
            shouldShowKioskLoadingSpinner(
                isLoadInFlight = true,
                hasEntries = false,
                hasLoadedSuccessfully = true,
            )
        )
        assertFalse(shouldSetKioskLoadingIndicator(hasEntries = true, hasLoadedSuccessfully = false))
        assertFalse(shouldSetKioskLoadingIndicator(hasEntries = false, hasLoadedSuccessfully = true))
    }

    @Test
    fun silentRefreshSkipsPendingPinAndInFlightLoad() {
        assertFalse(
            shouldSkipKioskSilentRefresh(
                pendingIds = emptySet(),
                isShowingPin = false,
                isLoadInFlight = false,
            )
        )
        assertTrue(shouldSkipKioskSilentRefresh(pendingIds = setOf("s1")))
        assertTrue(
            shouldSkipKioskSilentRefresh(
                pendingIds = emptySet(),
                isShowingPin = true,
                isLoadInFlight = false,
            )
        )
        assertTrue(
            shouldSkipKioskSilentRefresh(
                pendingIds = emptySet(),
                isShowingPin = false,
                isLoadInFlight = true,
            )
        )
    }

    @Test
    fun failedEmptyLoadIsNotNoClasses() {
        assertEquals(
            KioskRosterPresentation.LoadFailed,
            kioskRosterPresentation(
                isLoadInFlight = false,
                hasEntries = false,
                hasLoadedSuccessfully = false,
                loadFailed = true,
            ),
        )
        assertTrue(shouldSurfaceKioskLoadError(hasEntries = false))
        assertFalse(shouldSurfaceKioskLoadError(hasEntries = true))
    }

    @Test
    fun successfulEmptyLoadIsNoClasses() {
        assertEquals(
            KioskRosterPresentation.NoClasses,
            kioskRosterPresentation(
                isLoadInFlight = false,
                hasEntries = false,
                hasLoadedSuccessfully = true,
                loadFailed = false,
            ),
        )
    }

    @Test
    fun failedRefreshKeepsRosterWhenEntriesExist() {
        assertEquals(
            KioskRosterPresentation.Roster,
            kioskRosterPresentation(
                isLoadInFlight = false,
                hasEntries = true,
                hasLoadedSuccessfully = true,
                loadFailed = true,
            ),
        )
    }

    @Test
    fun inFlightFirstLoadPresentsSpinner() {
        assertEquals(
            KioskRosterPresentation.FullScreenLoading,
            kioskRosterPresentation(
                isLoadInFlight = true,
                hasEntries = false,
                hasLoadedSuccessfully = false,
                loadFailed = false,
            ),
        )
    }

    @Test
    fun keepLocalPendingEntryOnlyWhenIdIsPending() {
        assertTrue(shouldKeepLocalPendingEntry("s1", setOf("s1")))
        assertFalse(shouldKeepLocalPendingEntry("s1", setOf("s2")))
        assertFalse(shouldKeepLocalPendingEntry("s1", emptySet()))
    }

    @Test
    fun mergeKeepsPendingLocalRowAndUpdatesOthers() {
        val localPending = entry("s1", AttendanceStatus.present)
        val localOther = entry("s2", AttendanceStatus.late)
        val remotePending = entry("s1", AttendanceStatus.absent)
        val remoteOther = entry("s2", AttendanceStatus.present)
        val remoteNew = entry("s3", AttendanceStatus.absent)

        val merged = mergeKioskEntriesPreservingPending(
            local = listOf(localPending, localOther),
            remote = listOf(remotePending, remoteOther, remoteNew),
            pendingIds = setOf("s1"),
        )

        assertEquals(listOf("s1", "s2", "s3"), merged.map { it.studentId })
        assertSame(localPending, merged[0])
        assertEquals(AttendanceStatus.present, merged[0].status)
        assertSame(remoteOther, merged[1])
        assertSame(remoteNew, merged[2])
    }

    @Test
    fun mergeWithoutPendingUsesRemoteSnapshot() {
        val local = listOf(entry("s1", AttendanceStatus.present))
        val remote = listOf(entry("s1", null), entry("s2", AttendanceStatus.late))
        val merged = mergeKioskEntriesPreservingPending(local, remote, pendingIds = emptySet())
        assertSame(remote, merged)
    }

    @Test
    fun mergePreservesPendingLocalRowMissingFromRemote() {
        val localPending = entry("s1", AttendanceStatus.late)
        val localKept = entry("s2", AttendanceStatus.present)
        val remoteKept = entry("s2", AttendanceStatus.absent)

        val merged = mergeKioskEntriesPreservingPending(
            local = listOf(localPending, localKept),
            remote = listOf(remoteKept),
            pendingIds = setOf("s1"),
        )

        assertEquals(listOf("s2", "s1"), merged.map { it.studentId })
        assertSame(remoteKept, merged[0])
        assertSame(localPending, merged[1])
    }

    @Test
    fun offlineBannerAndUnlockCopyAreStudentFacing() {
        assertEquals("No internet — use the paper sheet. Taps will not save.", KIOSK_OFFLINE_BANNER)
        assertEquals("hold to unlock", KIOSK_UNLOCK_CONTENT_DESCRIPTION)
        assertEquals(30_000L, KIOSK_SILENT_REFRESH_MS)
        assertEquals(1_500L, KIOSK_UNLOCK_LONG_PRESS_MS)
    }
}
