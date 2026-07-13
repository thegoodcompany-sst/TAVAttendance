package com.example.tavattendance

import com.example.tavattendance.core.asUserMessage
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the error-message mapper used to surface failures across the admin screens.
 * Pure function, runs on the host JVM.
 */
class UiErrorTest {

    @Test
    fun usesExceptionMessage_whenPresent() {
        val msg = RuntimeException("network down").asUserMessage("Couldn't save class")
        assertEquals("Couldn't save class: network down", msg)
    }

    @Test
    fun fallsBackToClassName_whenMessageNull() {
        val msg = IllegalStateException().asUserMessage("Failed to load classes")
        assertEquals("Failed to load classes: IllegalStateException", msg)
    }
}
