package com.example.tavattendance

import com.example.tavattendance.data.models.Dismissal
import com.example.tavattendance.data.models.ParentMessage
import com.example.tavattendance.data.models.ResultSlip
import com.example.tavattendance.data.models.Student
import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParentRpcShapeTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun safeMessageDirectionDoesNotNeedActorIds() {
        val parent: ParentMessage = json.decodeFromString(
            """{"id":"10000000-0000-0000-0000-000000000001","student_id":"20000000-0000-0000-0000-000000000002","subject":null,"body":"Hello","sent_at":null,"read_at":null,"is_from_parent":true}"""
        )
        val centre: ParentMessage = json.decodeFromString(
            """{"id":"30000000-0000-0000-0000-000000000003","student_id":"20000000-0000-0000-0000-000000000002","subject":null,"body":"Reply","sent_at":null,"read_at":null,"is_from_parent":false}"""
        )

        assertTrue(parent.isFromParent)
        assertFalse(centre.isFromParent)
        assertNull(parent.senderId)
        assertNull(parent.recipientId)
    }

    @Test
    fun safeDismissalAndChildShapesOmitStaffAndStorageFields() {
        val dismissal: Dismissal = json.decodeFromString(
            """{"id":"10000000-0000-0000-0000-000000000001","student_id":"20000000-0000-0000-0000-000000000002","dismissed_at":null,"safely_home_at":null}"""
        )
        val child: Student = json.decodeFromString(
            """{"id":"20000000-0000-0000-0000-000000000002","full_name":"Child","school":null,"year_of_study":null,"is_active":true}"""
        )
        val result: ResultSlip = json.decodeFromString(
            """{"id":"50000000-0000-0000-0000-000000000005","student_id":"20000000-0000-0000-0000-000000000002","exam_name":"CA1","exam_date":"2026-07-01","subject":"Math","score":9,"max_score":10,"file_path":null,"uploaded_at":null,"acknowledged_at":null}"""
        )

        assertNull(dismissal.sessionId)
        assertNull(child.avatarUrl)
        assertTrue(result.isAcknowledged.not())
    }
}
