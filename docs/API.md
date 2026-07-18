# TAVA Attendance — iOS Integration Guide

This document is the contract between the backend (Supabase) and the iOS app.
Every section includes working Swift code using the [Supabase Swift SDK](https://github.com/supabase/supabase-swift).

---

## Table of Contents

1. [Setup](#1-setup)
2. [Authentication](#2-authentication)
3. [Data Models](#3-data-models)
4. [Core Queries](#4-core-queries)
5. [Attendance Flow (Tutor)](#5-attendance-flow-tutor)
6. [Offline Sync](#6-offline-sync)
7. [Real-Time (Admin Dashboard)](#7-real-time-admin-dashboard)
8. [Parent Views](#8-parent-views)
9. [Error Handling Reference](#9-error-handling-reference)

---

## 1. Setup

### 1.1 Install the SDK

In `Package.swift` or via Xcode's package manager:

```
https://github.com/supabase/supabase-swift
```

Minimum version: **2.x**. Import: `import Supabase`.

### 1.2 Shared Client

Create a single `SupabaseClient` instance and share it across the app (singleton or environment object).
Credentials are never hardcoded in source. Copy `Config.xcconfig.example` → `Config.xcconfig`
(gitignored) and fill in `SUPABASE_PROJECT_URL` / `SUPABASE_ANON_KEY`. `project.yml` (XcodeGen)
wires those xcconfig build settings into `Info.plist`, which the client reads at runtime:

```swift
// SupabaseManager.swift
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            fatalError("Supabase config missing. Add SUPABASE_PROJECT_URL and SUPABASE_ANON_KEY to Config.xcconfig (copy from Config.xcconfig.example).")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
```

> Get the project URL and anon key from **Supabase Dashboard → Settings → API**.
> Never commit the service role key to source control, and never commit `Config.xcconfig` itself.
> The anon key is safe for client use because RLS enforces access control.

---

## 2. Authentication

TAVA uses **invite-only** accounts. Admins invite users from the Supabase Dashboard or via the service role key (server-side only). Sign-up is disabled in `config.toml`.

### 2.1 Sign In

```swift
func signIn(email: String, password: String) async throws {
    try await SupabaseManager.shared.client.auth.signIn(
        email: email,
        password: password
    )
}
```

### 2.2 Observe Auth State

Use this in your root view or AppDelegate to react to login/logout:

```swift
// In your @main App struct or root ViewModel
for await state in SupabaseManager.shared.client.auth.authStateChanges {
    switch state.event {
    case .signedIn:
        // Navigate to main app
    case .signedOut:
        // Navigate to login screen
    default:
        break
    }
}
```

### 2.3 Get Current User & Role

The user's role (`admin`, `tutor`, `parent`) is stored in the `profiles` table.

```swift
struct Profile: Decodable {
    let id: UUID
    let fullName: String
    let role: String
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, phone
        case fullName = "full_name"
        case role
    }
}

func fetchMyProfile() async throws -> Profile {
    let userId = SupabaseManager.shared.client.auth.currentUser!.id
    return try await SupabaseManager.shared.client
        .from("profiles")
        .select()
        .eq("id", value: userId)
        .single()
        .execute()
        .value
}
```

### 2.4 Sign Out

```swift
try await SupabaseManager.shared.client.auth.signOut()
```

### 2.5 Session Persistence

The SDK persists the session to the iOS Keychain automatically. On app launch, check:

```swift
if let session = try? await SupabaseManager.shared.client.auth.session {
    // User is already logged in — skip login screen
}
```

---

## 3. Data Models

Define these `Codable` structs in Swift. Column names use `snake_case` in Postgres; use `CodingKeys` to map to Swift's `camelCase`.

```swift
// Models.swift
import Foundation

struct TAVClass: Codable, Identifiable {
    let id: UUID
    let name: String
    let subject: String?
    let level: String?
    let scheduleDay: String?
    let scheduleTime: String?   // "19:00:00" — parse with DateFormatter
    let durationMinutes: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, subject, level
        case scheduleDay      = "schedule_day"
        case scheduleTime     = "schedule_time"
        case durationMinutes  = "duration_minutes"
        case isActive         = "is_active"
    }
}

struct Student: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let school: String?
    let yearOfStudy: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, school
        case fullName     = "full_name"
        case yearOfStudy  = "year_of_study"
        case isActive     = "is_active"
    }
}

struct Session: Codable, Identifiable {
    let id: UUID
    let classId: UUID
    let sessionDate: String   // "2026-05-20" — parse with ISO8601DateFormatter
    let topic: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, topic, notes
        case classId     = "class_id"
        case sessionDate = "session_date"
    }
}

enum AttendanceStatus: String, Codable, CaseIterable {
    case present, absent, late, excused
}

struct AttendanceRecord: Codable, Identifiable {
    let id: UUID?                    // nil before server-assigned
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    let markedBy: UUID?
    let markedAt: Date?
    var notes: String?
    let clientMutationId: String     // UUID().uuidString, generated on-device

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case sessionId         = "session_id"
        case studentId         = "student_id"
        case markedBy          = "marked_by"
        case markedAt          = "marked_at"
        case clientMutationId  = "client_mutation_id"
    }
}

// Returned by get_session_roster() RPC
struct RosterEntry: Codable, Identifiable {
    let studentId: UUID
    let fullName: String
    let attendanceId: UUID?
    var status: AttendanceStatus?
    let markedAt: Date?
    var notes: String?

    var id: UUID { studentId }

    enum CodingKeys: String, CodingKey {
        case status, notes
        case studentId    = "student_id"
        case fullName     = "full_name"
        case attendanceId = "attendance_id"
        case markedAt     = "marked_at"
    }
}
```

---

## 4. Core Queries

All queries are automatically scoped by RLS — a tutor only receives their own classes; a parent only receives their children's data.

### 4.1 Fetch Active Classes (Tutor / Admin)

```swift
func fetchMyClasses() async throws -> [TAVClass] {
    return try await SupabaseManager.shared.client
        .from("classes")
        .select()
        .eq("is_active", value: true)
        .order("name")
        .execute()
        .value
}
```

### 4.2 Fetch Sessions for a Class

```swift
func fetchSessions(for classId: UUID) async throws -> [Session] {
    return try await SupabaseManager.shared.client
        .from("sessions")
        .select()
        .eq("class_id", value: classId)
        .order("session_date", ascending: false)
        .execute()
        .value
}
```

### 4.3 Create or Fetch Today's Session

The tutor taps "Start Class" → the app ensures a session row exists for today.

```swift
func getOrCreateSession(classId: UUID, date: String) async throws -> Session {
    // Try to find existing
    let existing: [Session] = try await SupabaseManager.shared.client
        .from("sessions")
        .select()
        .eq("class_id", value: classId)
        .eq("session_date", value: date)
        .execute()
        .value

    if let session = existing.first { return session }

    // Create if it doesn't exist
    let new = Session(
        id: UUID(),
        classId: classId,
        sessionDate: date,
        topic: nil,
        notes: nil
    )
    return try await SupabaseManager.shared.client
        .from("sessions")
        .insert(new)
        .select()
        .single()
        .execute()
        .value
}
```

### 4.4 Fetch Session Roster (Students + Current Status)

Uses the `get_session_roster` database function.

```swift
func fetchRoster(sessionId: UUID) async throws -> [RosterEntry] {
    return try await SupabaseManager.shared.client
        .rpc("get_session_roster", params: ["p_session_id": sessionId.uuidString])
        .execute()
        .value
}
```

### 4.5 Create a Student with Consent

Student creation must use `create_student_with_consent`; direct authenticated
inserts into `students` are denied. The admin-guarded RPC creates the student
and mandatory consent-ledger entry atomically, stamps `auth.uid()` as the actor,
and reads the current data-protection-notice version on the server.

```swift
struct CreateStudentWithConsentParams: Encodable {
    let fullName: String
    let school: String?
    let yearOfStudy: String?
    let sourceNote: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "p_full_name"
        case school = "p_school"
        case yearOfStudy = "p_year_of_study"
        case sourceNote = "p_source_note"
    }
}

func createStudentWithConsent(
    _ student: StudentInsert,
    sourceNote: String
) async throws -> Student {
    try await SupabaseManager.shared.client
        .rpc("create_student_with_consent", params: CreateStudentWithConsentParams(
            fullName: student.fullName,
            school: student.school,
            yearOfStudy: student.yearOfStudy,
            sourceNote: sourceNote
        ))
        .execute()
        .value
}
```

---

## 5. Attendance Flow (Tutor)

### 5.1 Mark a Single Student (Online)

Use a separate insert-only struct that omits `id` from the encoded payload. If you include `"id": null` in the upsert body, some SDK versions reject it.

```swift
// AttendanceInsert — omits the server-assigned id
struct AttendanceInsert: Encodable {
    let sessionId: UUID
    let studentId: UUID
    let status: AttendanceStatus
    let notes: String?
    let clientMutationId: String

    enum CodingKeys: String, CodingKey {
        case status, notes
        case sessionId        = "session_id"
        case studentId        = "student_id"
        case clientMutationId = "client_mutation_id"
    }
}

func markAttendance(
    sessionId: UUID,
    studentId: UUID,
    status: AttendanceStatus,
    notes: String? = nil
) async throws {
    let record = AttendanceInsert(
        sessionId:        sessionId,
        studentId:        studentId,
        status:           status,
        notes:            notes,
        clientMutationId: UUID().uuidString
    )
    try await SupabaseManager.shared.client
        .from("attendance_records")
        .upsert(record, onConflict: "session_id,student_id")
        .execute()
}
```

`onConflict: "session_id,student_id"` means calling this function twice for the same student in the same session updates, not duplicates.

### 5.2 Recommended UI Flow

```
TutorHomeView
  └─ ClassListView          [fetchMyClasses()]
       └─ SessionView        [getOrCreateSession(), fetchRoster()]
            └─ RosterRow    [markAttendance() or queue locally]
```

Each `RosterRow` shows the student's name and four status buttons (P / A / L / E). Tapping one calls `markAttendance` immediately if online, or queues the record locally if offline (see §6).

---

## 6. Offline Sync

### 6.1 Overview

The app must work without internet. The strategy:

1. **Before class** — download and cache the class roster and today's session to `UserDefaults` or CoreData.
2. **During class** — mark attendance locally. Each pending record has `isSynced = false`.
3. **On reconnect** — call the `sync_attendance` Postgres function with all unsynced records.

### 6.2 Local Cache Model

```swift
// PendingAttendance.swift — stored in UserDefaults or CoreData
struct PendingAttendanceRecord: Codable {
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    var notes: String?
    let clientMutationId: String   // Never changes once created
    let markedAt: Date
    var isSynced: Bool
}
```

### 6.3 Queue a Record Locally

```swift
func queueAttendanceLocally(
    sessionId: UUID,
    studentId: UUID,
    status: AttendanceStatus
) {
    var pending = loadPendingFromDisk()
    let idx = pending.firstIndex { $0.sessionId == sessionId && $0.studentId == studentId }

    if let i = idx {
        // Update existing pending record (user changed their mind)
        pending[i].status   = status
        pending[i].isSynced = false
    } else {
        pending.append(PendingAttendanceRecord(
            sessionId:         sessionId,
            studentId:         studentId,
            status:            status,
            notes:             nil,
            clientMutationId:  UUID().uuidString,
            markedAt:          Date(),
            isSynced:          false
        ))
    }
    savePendingToDisk(pending)
}
```

### 6.4 Sync on Reconnect

Call this when `NWPathMonitor` reports connectivity restored:

```swift
func syncPendingAttendance() async throws {
    var pending = loadPendingFromDisk()
    let unsynced = pending.filter { !$0.isSynced }
    guard !unsynced.isEmpty else { return }

    // Build JSON array expected by sync_attendance()
    let payload = unsynced.map { r in
        [
            "session_id":          r.sessionId.uuidString,
            "student_id":          r.studentId.uuidString,
            "status":              r.status.rawValue,
            "notes":               r.notes ?? "",
            "client_mutation_id":  r.clientMutationId,
            "marked_at":           ISO8601DateFormatter().string(from: r.markedAt)
        ]
    }

    let result: [String: Int] = try await SupabaseManager.shared.client
        .rpc("sync_attendance", params: ["records": payload])
        .execute()
        .value

    // Mark local records as synced
    let syncedIds = Set(unsynced.map(\.clientMutationId))
    for i in pending.indices where syncedIds.contains(pending[i].clientMutationId) {
        pending[i].isSynced = true
    }
    savePendingToDisk(pending)

    print("Synced \(result["synced"] ?? 0), skipped \(result["skipped"] ?? 0)")
}
```

### 6.5 Connectivity Monitor

```swift
import Network

class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
```

In your `SessionView`:

```swift
@StateObject private var network = NetworkMonitor()

// When marking attendance:
if network.isConnected {
    try await markAttendance(sessionId: session.id, studentId: student.id, status: status)
} else {
    queueAttendanceLocally(sessionId: session.id, studentId: student.id, status: status)
}

// On each appearance when connected:
.onChange(of: network.isConnected) { connected in
    if connected { Task { try? await syncPendingAttendance() } }
}
```

### 6.6 Conflict Resolution

If a student's attendance was marked on two devices while offline (e.g. two tutors), the server applies **last-write-wins**: whichever `marked_at` timestamp is later wins. The `client_mutation_id` guarantees a retry from the same device never creates duplicates.

---

## 7. Real-Time (Admin Dashboard)

The admin web dashboard (Phase 2+) and any live summary view can subscribe to real-time updates.

### 7.1 Subscribe to New Attendance Records

> **Note:** Realtime API method names (`postgresChange`, `decodeRecord`) vary between SDK minor versions. Verify against the [supabase-swift README](https://github.com/supabase/supabase-swift) for your installed version before use.

```swift
func subscribeToAttendance(sessionId: UUID, onRecord: @escaping (AttendanceRecord) -> Void) -> RealtimeChannelV2 {
    let channel = SupabaseManager.shared.client
        .channel("session-\(sessionId)")

    Task {
        let changes = channel.postgresChange(
            InsertAction.self,
            table: "attendance_records",
            filter: "session_id=eq.\(sessionId)"
        )
        await channel.subscribe()
        for await change in changes {
            if let record = try? change.decodeRecord(as: AttendanceRecord.self) {
                onRecord(record)
            }
        }
    }
    return channel
}
```

To unsubscribe when the view disappears:

```swift
await channel.unsubscribe()
```

---

## 8. Parent Views

Parents see only their own children (enforced by RLS — no extra filtering needed in the app).

### 8.1 Fetch Children

```swift
func fetchMyChildren() async throws -> [Student] {
    return try await SupabaseManager.shared.client
        .from("students")
        .select()
        .eq("is_active", value: true)
        .order("full_name")
        .execute()
        .value
}
```

### 8.2 Fetch Attendance History for a Child

```swift
func fetchAttendanceHistory(
    studentId: UUID,
    limit: Int = 30
) async throws -> [AttendanceRecord] {
    return try await SupabaseManager.shared.client
        .from("attendance_records")
        .select("""
            *,
            sessions!inner(session_date, class_id,
                classes!inner(name))
        """)
        .eq("student_id", value: studentId)
        .order("sessions.session_date", ascending: false)
        .limit(limit)
        .execute()
        .value
}
```

### 8.3 Attendance Summary

```swift
func fetchAttendanceSummary(
    studentId: UUID
) async throws -> [AttendanceSummaryRow] {
    return try await SupabaseManager.shared.client
        .from("attendance_summary")   // this is the VIEW created in 003_functions_triggers.sql
        .select()
        .eq("student_id", value: studentId)
        .execute()
        .value
}
```

---

## 9. Error Handling Reference

Supabase Swift SDK throws typed `PostgrestError` values. Handle them at the call site:

```swift
do {
    try await markAttendance(...)
} catch let error as PostgrestError {
    switch error.code {
    case "42501":  // RLS violation — user not authorised
        showAlert("You are not allowed to edit this record.")
    case "23505":  // Unique violation (should not happen with upsert, but just in case)
        break
    default:
        showAlert("Database error: \(error.message)")
    }
} catch {
    showAlert("Network error: \(error.localizedDescription)")
}
```

### Common Error Codes

| Code  | Meaning                                         | Likely Cause                          |
|-------|-------------------------------------------------|---------------------------------------|
| 42501 | Insufficient privilege (RLS blocked)            | User's role doesn't allow this action |
| 23505 | Unique constraint violation                     | Duplicate `client_mutation_id`        |
| PGRST116 | `single()` returned zero rows                | Session or student not found          |
| PGRST301 | JWT expired                                  | Call `signIn()` again                 |

---

## Appendix: Database Schema Quick Reference

```
profiles           id, full_name, role (admin|tutor|parent), phone
students           id, full_name, school, year_of_study, is_active
parent_student_links  parent_id → profiles, student_id → students
classes            id, name, subject, level, schedule_day, schedule_time
class_tutor_assignments  class_id, tutor_id, assigned_from, assigned_until
enrollments        student_id, class_id, is_active
sessions           id, class_id, session_date  ← UNIQUE per class per day
attendance_records id, session_id, student_id, status, client_mutation_id
audit_log          table_name, record_id, action, old_data, new_data, changed_at
```

Phase 2 tables (schema exists, not yet wired): `result_slips`, `messages`, `awards`
Phase 3 tables (schema exists, not yet wired): `dismissals`, `food_polls`, `food_poll_responses`

## Retrospective sessions (migration 037; flag `retrospective_sessions`)

Past-session management is server-gated and available only to admins and tutors
assigned to the session's class. All functions reject Study Space and dates on or
after today. Historical attendance is online-only and server-timestamped; clients
must not send these writes through `sync_attendance` or the offline pending queue.

| RPC | Purpose |
|---|---|
| `create_retrospective_session(class_id, session_date, topic, notes, sub_tutor_id)` | Create one session before today; class/date duplicates fail. |
| `update_retrospective_session(session_id, topic, notes, sub_tutor_id)` | Update mutable details only; class/date remain immutable. |
| `get_retrospective_session_roster(session_id)` | Enrollment-on-date roster unioned with attendance-only students. |
| `mark_retrospective_attendance(session_id, student_id, status)` | Upsert attendance on an ended past session using the server clock. |

The notes argument additionally requires the `session_notes` flag. Adding a
student through attendance never inserts or updates an `enrollments` row. Admins
may add any active student; tutors are limited to students visible under the
existing student policy.
