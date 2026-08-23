package com.example.tavattendance

import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.store.PendingAttendanceRecord
import com.example.tavattendance.data.store.PendingQueueCipher
import com.example.tavattendance.data.store.correctedPendingRecord
import com.example.tavattendance.data.store.decodePendingQueue
import com.example.tavattendance.data.store.encodePendingQueue
import com.example.tavattendance.data.store.observedServerMarkedAt
import com.example.tavattendance.data.store.pendingRecordsBelongToOwner
import com.example.tavattendance.data.store.recordsAfterSync
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.KeyGenerator

class PendingAttendanceStoreTest {
    private val owner = "10000000-0000-0000-0000-000000000001"

    private fun record(id: String, synced: Boolean = false, ownerUserId: String = owner) = PendingAttendanceRecord(
        ownerUserId = ownerUserId,
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

    @Test
    fun queueRoundTripRequiresMatchingEnvelopeAndRecordOwner() {
        val encoded = requireNotNull(encodePendingQueue(owner, listOf(record("pending"))))

        assertEquals(listOf("pending"), decodePendingQueue(encoded, owner)?.map { it.clientMutationId })
        assertNull(decodePendingQueue(encoded, "20000000-0000-0000-0000-000000000002"))
    }

    @Test
    fun clearMutationRoundTripsWithNullStatus() {
        val encoded = requireNotNull(encodePendingQueue(owner, listOf(record("clear").copy(status = null))))

        assertNull(decodePendingQueue(encoded, owner)?.single()?.status)
    }

    @Test
    fun versionTwoQueueMigratesKnownMarksAndUnknownStatusToClear() {
        val legacy = """{
            "version":2,
            "ownerUserId":"$owner",
            "records":[
                {"ownerUserId":"$owner","sessionId":"s1","studentId":"a","status":"present","clientMutationId":"m1","markedAt":"2026-07-15T00:00:00Z"},
                {"ownerUserId":"$owner","sessionId":"s1","studentId":"b","status":"retired","clientMutationId":"m2","markedAt":"2026-07-15T00:00:00Z"}
            ]
        }""".trimIndent()

        val migrated = requireNotNull(decodePendingQueue(legacy, owner))
        assertEquals(AttendanceStatus.present, migrated[0].status)
        assertNull(migrated[1].status)
    }

    @Test
    fun legacyUnownedArrayAndMixedOwnerQueueFailClosed() {
        val foreign = record("foreign", ownerUserId = "20000000-0000-0000-0000-000000000002")
        assertNull(decodePendingQueue("[]", owner))
        assertNull(encodePendingQueue(owner, listOf(foreign)))
        assertEquals(false, pendingRecordsBelongToOwner(listOf(foreign), owner))
    }

    @Test
    fun observedMarkedAtRoundTripsIsoAndJsonNull() {
        val observed = record("observed").copy(
            observedMarkedAt = "2026-08-23T12:00:00Z",
            didObserveRow = true,
        )
        val none = record("none").copy(observedMarkedAt = null, didObserveRow = true)

        val encodedObserved = requireNotNull(encodePendingQueue(owner, listOf(observed)))
        val encodedNone = requireNotNull(encodePendingQueue(owner, listOf(none)))
        val envelope = Json.parseToJsonElement(encodedNone).jsonObject
        assertEquals(4, envelope["version"]?.jsonPrimitive?.int)

        assertEquals("2026-08-23T12:00:00Z", decodePendingQueue(encodedObserved, owner)?.single()?.observedMarkedAt)
        val decodedNone = requireNotNull(decodePendingQueue(encodedNone, owner)?.single())
        assertNull(decodedNone.observedMarkedAt)
        assertTrue(decodedNone.didObserveRow)
        val noneJson = envelope["records"]!!.jsonArray[0].jsonObject
        assertTrue(noneJson.containsKey("observedMarkedAt"))
        assertEquals(JsonNull, noneJson["observedMarkedAt"])
        assertEquals(true, noneJson["didObserveRow"]?.jsonPrimitive?.boolean)
    }

    @Test
    fun versionThreeQueueOmitsObservationAsUnknown() {
        val legacy = """{
            "version":3,
            "ownerUserId":"$owner",
            "records":[
                {"ownerUserId":"$owner","sessionId":"s1","studentId":"a","status":"present","clientMutationId":"m1","markedAt":"2026-07-15T00:00:00Z","isSynced":false}
            ]
        }""".trimIndent()

        val migrated = requireNotNull(decodePendingQueue(legacy, owner)).single()
        assertEquals(AttendanceStatus.present, migrated.status)
        assertEquals("m1", migrated.clientMutationId)
        assertNull(migrated.observedMarkedAt)
        assertFalse(migrated.didObserveRow)
    }

    @Test
    fun observedServerMarkedAtCapturesRosterTimestampOnlyWhenStatusPresent() {
        assertEquals(
            "2026-08-23T12:00:00Z",
            observedServerMarkedAt(AttendanceStatus.present, "2026-08-23T12:00:00Z"),
        )
        assertNull(observedServerMarkedAt(null, "2026-08-23T12:00:00Z"))
        assertNull(observedServerMarkedAt(AttendanceStatus.late, null))
    }

    @Test
    fun inPlaceCorrectionKeepsObservedMarkedAtAndRotatesMutationId() {
        val original = record("m1").copy(
            status = AttendanceStatus.present,
            observedMarkedAt = "2026-08-23T12:00:00Z",
            didObserveRow = true,
        )
        val corrected = correctedPendingRecord(
            existing = original,
            status = AttendanceStatus.late,
            notes = null,
            absenceInformed = null,
            clientMutationId = "m2",
            markedAt = "2026-08-23T12:05:00Z",
        )

        assertEquals("2026-08-23T12:00:00Z", corrected.observedMarkedAt)
        assertTrue(corrected.didObserveRow)
        assertEquals("m2", corrected.clientMutationId)
        assertEquals("2026-08-23T12:05:00Z", corrected.markedAt)
        assertEquals(AttendanceStatus.late, corrected.status)
        assertFalse(corrected.isSynced)
    }

    @Test
    fun observedMarkedAtDoesNotWeakenForeignOrMixedOwnerFailClosed() {
        val foreign = record("foreign", ownerUserId = "20000000-0000-0000-0000-000000000002")
            .copy(observedMarkedAt = "2026-08-23T12:00:00Z")
        assertNull(encodePendingQueue(owner, listOf(foreign)))
        assertEquals(false, pendingRecordsBelongToOwner(listOf(foreign), owner))
    }

    @Test
    fun queueEncryptionRejectsTampering() {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val plaintext = requireNotNull(encodePendingQueue(owner, listOf(record("private"))))
        val encrypted = PendingQueueCipher.seal(plaintext, key)

        assertNotEquals(plaintext, encrypted)
        assertEquals(plaintext, PendingQueueCipher.open(encrypted, key))

        val replacement = if (encrypted.last() == 'A') 'B' else 'A'
        val tampered = encrypted.dropLast(1) + replacement
        assertThrows(Exception::class.java) {
            PendingQueueCipher.open(tampered, key)
        }
    }
}
