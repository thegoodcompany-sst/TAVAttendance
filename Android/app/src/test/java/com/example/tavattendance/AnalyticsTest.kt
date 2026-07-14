package com.example.tavattendance

import com.example.tavattendance.core.Analytics
import com.example.tavattendance.core.AnalyticsEventType
import com.example.tavattendance.core.AppEvent
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Buffer + drop-on-failure behaviour of the analytics buffer. Pure JVM — never
 * touches Android or Supabase. Mirrors the iOS XCTest for the same seam: a failed
 * flush must discard the batch (no offline queue), and the buffer must stay bounded.
 */
class AnalyticsTest {

    @Before
    fun clearBuffer() {
        Analytics.buffer.clear()
    }

    @Test
    fun flush_dropsBatch_evenWhenSinkFails() = runBlocking {
        Analytics.record(AnalyticsEventType.OPS, "app_launch")
        Analytics.record(AnalyticsEventType.OPS, "kiosk_load")
        assertEquals(2, Analytics.buffer.size)

        var received: List<AppEvent>? = null
        Analytics.flush { batch ->
            received = batch
            throw RuntimeException("offline")
        }

        assertEquals(2, received?.size)              // the sink saw the batch
        assertTrue(Analytics.buffer.isEmpty())        // dropped despite the failure
    }

    @Test
    fun flush_isNoOp_whenBufferEmpty() = runBlocking {
        var called = false
        Analytics.flush { called = true }
        assertTrue(!called)
    }

    @Test
    fun record_capsBufferAtMax_sheddingOldest() {
        repeat(Analytics.MAX_BUFFERED + 10) { i ->
            Analytics.record(AnalyticsEventType.OPS, "e$i")
        }
        assertEquals(Analytics.MAX_BUFFERED, Analytics.buffer.size)
        // The 10 oldest were shed, so the first survivor is e10.
        assertEquals("e10", Analytics.buffer.first().name)
    }
}
