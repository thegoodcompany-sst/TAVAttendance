package com.example.tavattendance

import com.example.tavattendance.data.service.SyncAttendancePayload
import com.example.tavattendance.data.service.encodeSyncAttendanceRecord
import com.example.tavattendance.data.service.parseSyncAttendanceCounts
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ObservedAttendanceCasTest {
    private fun payload(observedMarkedAt: String?, didObserveRow: Boolean) = SyncAttendancePayload(
        sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        studentId = "11111111-2222-3333-4444-555555555555",
        status = "present",
        notes = "",
        clientMutationId = "m1",
        markedAt = "2026-08-23T12:05:00Z",
        observedMarkedAt = observedMarkedAt,
        didObserveRow = didObserveRow,
    )

    @Test
    fun observedMarkedAtIsEncodedWhenObservedIncludingJsonNull() {
        val unmarked = encodeSyncAttendanceRecord(payload(null, didObserveRow = true))
        assertTrue(unmarked.containsKey("observed_marked_at"))
        assertEquals(JsonNull, unmarked["observed_marked_at"])

        val iso = encodeSyncAttendanceRecord(payload("2026-08-23T12:00:00Z", didObserveRow = true))
        assertEquals("2026-08-23T12:00:00Z", iso["observed_marked_at"]?.jsonPrimitive?.content)

        val unknown = encodeSyncAttendanceRecord(payload(null, didObserveRow = false))
        assertFalse(unknown.containsKey("observed_marked_at"))
    }

    @Test
    fun skippedConflictDefaultsToZeroAndIsReadWhenPresent() {
        val missing = parseSyncAttendanceCounts(mapOf("synced" to 1, "skipped" to 0))
        assertEquals(0, missing.skippedConflict)
        assertEquals(0, missing.blockedEndedSession)
        assertEquals(1, missing.synced)

        val present = parseSyncAttendanceCounts(
            mapOf(
                "synced" to 2,
                "skipped" to 1,
                "blocked_ended_session" to 3,
                "skipped_conflict" to 4,
            )
        )
        assertEquals(2, present.synced)
        assertEquals(1, present.skipped)
        assertEquals(3, present.blockedEndedSession)
        assertEquals(4, present.skippedConflict)
    }
}
