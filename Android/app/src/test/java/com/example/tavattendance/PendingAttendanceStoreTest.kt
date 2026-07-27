package com.example.tavattendance

import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.store.PendingAttendanceRecord
import com.example.tavattendance.data.store.PendingQueueCipher
import com.example.tavattendance.data.store.decodePendingQueue
import com.example.tavattendance.data.store.encodePendingQueue
import com.example.tavattendance.data.store.pendingRecordsBelongToOwner
import com.example.tavattendance.data.store.recordsAfterSync
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
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
    fun legacyUnownedArrayAndMixedOwnerQueueFailClosed() {
        val foreign = record("foreign", ownerUserId = "20000000-0000-0000-0000-000000000002")
        assertNull(decodePendingQueue("[]", owner))
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
