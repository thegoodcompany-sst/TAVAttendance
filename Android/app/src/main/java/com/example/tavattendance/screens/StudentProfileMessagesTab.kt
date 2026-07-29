package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.core.rememberSnackbarError
import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.ParentMessage
import com.example.tavattendance.data.models.ResultSlip
import com.example.tavattendance.data.models.ResultSlipInputValidation
import com.example.tavattendance.data.models.ResultSubject
import com.example.tavattendance.data.service.AttendanceService
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.util.*

@Composable
internal fun MessagesTabContent(
    messages: List<ParentMessage>,
    isLoading: Boolean,
    error: String?,
    isSending: Boolean,
    onRetry: () -> Unit,
    onSend: (subject: String?, body: String, clear: () -> Unit) -> Unit
) {
    var subject by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
    }

    Column(modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp)) {
        Box(modifier = Modifier.weight(1f, fill = false).fillMaxWidth().heightIn(min = 120.dp, max = 320.dp)) {
            when {
                isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                error != null && messages.isEmpty() -> Column(
                    modifier = Modifier.fillMaxSize().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onRetry) { Text("Retry") }
                }
                messages.isEmpty() -> Text(
                    "No messages yet. Send a message to TAVA about this child.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(8.dp)
                )
                else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    items(messages, key = { it.id }) { msg ->
                        val fromParent = msg.isFromParent
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            horizontalArrangement = if (fromParent) Arrangement.End else Arrangement.Start
                        ) {
                            Column(
                                modifier = Modifier
                                    .widthIn(max = 280.dp)
                                    .background(
                                        if (fromParent) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.surfaceVariant,
                                        RoundedCornerShape(14.dp)
                                    )
                                    .padding(10.dp)
                            ) {
                                msg.subject?.takeIf { it.isNotBlank() }?.let {
                                    Text(
                                        it,
                                        style = MaterialTheme.typography.labelMedium,
                                        color = if (fromParent) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                        else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    msg.body,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = if (fromParent) MaterialTheme.colorScheme.onPrimary
                                    else MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = subject,
            onValueChange = { subject = it },
            label = { Text("Subject (optional)") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = body,
                onValueChange = { body = it },
                label = { Text("Message") },
                modifier = Modifier.weight(1f),
                minLines = 1,
                maxLines = 4
            )
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = {
                    onSend(subject, body) {
                        subject = ""
                        body = ""
                    }
                },
                enabled = !isSending && body.isNotBlank()
            ) {
                if (isSending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text("Send")
            }
        }
    }
}
