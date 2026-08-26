package com.example.tavattendance

import com.example.tavattendance.core.SignedInDestination
import com.example.tavattendance.core.signedInDestination
import org.junit.Assert.assertEquals
import org.junit.Test

class SignedInDestinationTest {
    @Test
    fun arrivalStationDoesNotFallThroughToTutor() {
        assertEquals(SignedInDestination.Admin, signedInDestination("admin"))
        assertEquals(SignedInDestination.Parent, signedInDestination("parent"))
        assertEquals(SignedInDestination.ArrivalStation, signedInDestination("arrival_station"))
        assertEquals(SignedInDestination.Tutor, signedInDestination("tutor"))
        assertEquals(SignedInDestination.Tutor, signedInDestination(null))
        assertEquals(SignedInDestination.Tutor, signedInDestination("unknown"))
    }
}
