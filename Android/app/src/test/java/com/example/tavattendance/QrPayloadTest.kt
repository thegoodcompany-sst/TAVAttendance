package com.example.tavattendance

import com.example.tavattendance.data.service.AttendanceService
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the kiosk QR payload parser (flag `qr_sign_in`). Mirrors the iOS
 * `testQRPayloadParsing` cases — pure function, runs on the host JVM.
 */
class QrPayloadTest {

    private val id = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

    @Test
    fun validUuid_isAccepted() {
        assertEquals(id, AttendanceService.studentIdFromQrPayload(id))
    }

    @Test
    fun uppercaseAndWhitespace_areNormalised() {
        assertEquals(id, AttendanceService.studentIdFromQrPayload(" ${id.uppercase()}\n"))
    }

    @Test
    fun emptyPayload_isRejected() {
        assertNull(AttendanceService.studentIdFromQrPayload(""))
    }

    @Test
    fun garbage_isRejected() {
        assertNull(AttendanceService.studentIdFromQrPayload("not-a-uuid"))
    }

    @Test
    fun urlWrappedUuid_isRejected() {
        assertNull(AttendanceService.studentIdFromQrPayload("https://example.com/$id"))
    }
}
