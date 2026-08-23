package com.example.tavattendance.screens.kiosk

import com.example.tavattendance.data.models.KioskEntry

internal const val KIOSK_SILENT_REFRESH_MS = 30_000L
internal const val KIOSK_UNLOCK_LONG_PRESS_MS = 1_500L

internal const val KIOSK_OFFLINE_BANNER =
    "No internet — use the paper sheet. Taps will not save."

internal const val KIOSK_UNLOCK_CONTENT_DESCRIPTION = "hold to unlock"

internal enum class KioskRosterPresentation {
    FullScreenLoading,
    LoadFailed,
    NoClasses,
    Roster,
}

/** Full-screen spinner unmounts the grid. Only the first fetch may do that. */
internal fun shouldShowKioskLoadingSpinner(
    isLoadInFlight: Boolean,
    hasEntries: Boolean,
    hasLoadedSuccessfully: Boolean,
): Boolean = isLoadInFlight && !hasEntries && !hasLoadedSuccessfully

internal fun shouldSetKioskLoadingIndicator(
    hasEntries: Boolean,
    hasLoadedSuccessfully: Boolean,
): Boolean = !hasEntries && !hasLoadedSuccessfully

internal fun shouldSkipKioskSilentRefresh(
    pendingIds: Set<String>,
    isShowingPin: Boolean = false,
    isLoadInFlight: Boolean = false,
): Boolean = pendingIds.isNotEmpty() || isShowingPin || isLoadInFlight

internal fun shouldKeepLocalPendingEntry(studentId: String, pendingIds: Set<String>): Boolean =
    studentId in pendingIds

internal fun shouldSurfaceKioskLoadError(hasEntries: Boolean): Boolean = !hasEntries

internal fun kioskRosterPresentation(
    isLoadInFlight: Boolean,
    hasEntries: Boolean,
    hasLoadedSuccessfully: Boolean,
    loadFailed: Boolean,
): KioskRosterPresentation {
    if (shouldShowKioskLoadingSpinner(isLoadInFlight, hasEntries, hasLoadedSuccessfully)) {
        return KioskRosterPresentation.FullScreenLoading
    }
    if (!hasEntries && loadFailed) return KioskRosterPresentation.LoadFailed
    if (!hasEntries) return KioskRosterPresentation.NoClasses
    return KioskRosterPresentation.Roster
}

/**
 * Keep in-flight local rows so a fetch that races a tap cannot revert optimistic status
 * or drop the card. Non-pending students take the fetched snapshot.
 */
internal fun mergeKioskEntriesPreservingPending(
    local: List<KioskEntry>,
    remote: List<KioskEntry>,
    pendingIds: Set<String>,
): List<KioskEntry> {
    if (pendingIds.isEmpty()) return remote
    val localById = local.associateBy { it.studentId }
    val seen = HashSet<String>(remote.size)
    val merged = remote.map { entry ->
        seen.add(entry.studentId)
        if (shouldKeepLocalPendingEntry(entry.studentId, pendingIds)) {
            localById[entry.studentId] ?: entry
        } else {
            entry
        }
    }
    if (seen.containsAll(pendingIds)) return merged
    val extras = local.filter {
        shouldKeepLocalPendingEntry(it.studentId, pendingIds) && it.studentId !in seen
    }
    return if (extras.isEmpty()) merged else merged + extras
}
