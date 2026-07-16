package com.example.tavattendance

import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.store.PendingAttendanceRecord
import com.example.tavattendance.data.store.recordsAfterSync
import org.junit.Assert.assertEquals
import org.junit.Test

class PendingAttendanceStoreTest {
    private fun record(id: String, synced: Boolean = false) = PendingAttendanceRecord(
        sessionId = "session",
        studentId = "student",
        status = AttendanceStatus.present,
        clientMutationId = id,
        markedAt = "2026-07-15T00:00:00Z",
        isSynced = synced,
    )

    @Test
    fun syncedAndLegacySyncedRecordsAreRemovedFromDeviceCache() {
        val remaining = recordsAfterSync(
            listOf(record("uploaded"), record("pending"), record("legacy", synced = true)),
            setOf("uploaded"),
        )

        assertEquals(listOf("pending"), remaining.map { it.clientMutationId })
    }
}
