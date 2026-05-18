# TAVA Attendance & Student Management Platform - Implementation Guide

## Overview

This document outlines the implementation of the TAVA Attendance MVP for iOS, focusing on efficient attendance tracking with a role-based interface and iPad-optimized UI for attendance takers.

## Implementation Summary

### ✅ Completed Features

#### 1. **Role-Based Sign-In**
- Users select a role (Attendance Taker, Admin, Parent) on the login screen
- Role selection is visual with icons and labels
- Selected role persists through the session and determines which UI is shown

#### 2. **Attendance Taker (Tutor) Interface**
- **iPad-Optimized Split View**: Classes on the sidebar, attendance marking in the detail view
- **Today's Session Management**: "Start Today's Class" button to create or retrieve today's session
- **Large Attendance Cards**: Grid layout with large touch-friendly buttons for marking attendance (P/A/L/E)
- **Color-Coded Status**: Green (Present), Red (Absent), Orange (Late), Blue (Excused)
- **Responsive Grid**: Adapts to screen size (3-4 columns depending on device orientation)
- **Real-time Feedback**: Instant visual feedback when marking attendance

#### 3. **Real-Time Sync**
- **Online Sync**: Attendance records are immediately synced to Supabase when online
- **Offline Queue**: Records are saved locally when offline using `PendingAttendanceStore`
- **Auto-Sync**: When network reconnects, pending records are automatically synced
- **Offline Indicator**: Orange wifi-slash icon shows network status

#### 4. **Data Security**
- Role-Based Access Control (RBAC) via Supabase RLS policies
- Only tutors can see their assigned classes and mark attendance
- Parents see only their children's records
- Admins have full access

#### 5. **Admin/Parent Interface**
- Traditional class list view with navigation to sessions
- Ability to view past attendance records
- Role-specific data visibility

### 📁 New/Modified Files

#### New Files Created:
- **`Views/AttendanceTaker/AttendanceTakerView.swift`**: Main split view for iPad attendance interface
- **`Views/AttendanceTaker/AttendanceDetailView.swift`**: Detail view with session controls and roster

#### Modified Files:
- **`Views/Auth/LoginView.swift`**: Added role selection UI
- **`Core/AuthManager.swift`**: Added `selectedRole` property and role parameter to `signIn()`
- **`Core/Models.swift`**: Added `Hashable` and `Equatable` to `UserRole` enum
- **`TAVAttendanceApp.swift`**: Conditional routing based on selected role

### 🔄 Application Flow

```
App Launch
    ↓
Auth Manager Checks Session
    ↓
├─ No Session → LoginView
│   ├─ User selects role (Tutor/Admin/Parent)
│   ├─ User enters email/password
│   └─ User signs in
│
└─ Session Exists → Route by Role
    ├─ Role == Tutor → AttendanceTakerView (Split View)
    │   ├─ Sidebar: Class List
    │   └─ Detail: Attendance Marking
    │
    └─ Other Roles → ClassListView (Traditional)
        ├─ Classes
        ├─ Sessions
        └─ Roster (View Only for Parents)
```

### 🎯 Key Architecture Decisions

1. **Split View for iPad**: Maximizes screen real estate on iPad devices
2. **Grid Layout for Attendance Cards**: Quick visual scanning and large touch targets
3. **Immediate Local Updates**: UI updates instantly before server confirmation for responsiveness
4. **Offline-First**: All attendance changes are queued locally with automatic sync
5. **Role-Based Routing**: Different users see fundamentally different experiences

### 🚀 How to Use

#### As an Attendance Taker (Tutor):
1. Sign in with email and password, selecting "Attendance Taker" role
2. Select a class from the sidebar
3. Click "Start Today's Class" to create or retrieve today's session
4. Mark each student's attendance by clicking P/A/L/E buttons
5. Changes sync automatically when online; offline changes are queued

#### As an Admin:
1. Sign in with "Admin" role
2. View all classes and sessions
3. Access administrative features (coming in Phase 2)

#### As a Parent:
1. Sign in with "Parent" role
2. View only their children's attendance records
3. Receive notifications (coming in Phase 2)

### 🔌 API Integration

All API calls go through `AttendanceService.shared`:

- **`fetchClasses()`**: Get tutor's assigned classes
- **`fetchSessions(classId:)`**: Get sessions for a class
- **`getOrCreateTodaySession(classId:)`**: Create/retrieve today's session
- **`fetchRoster(sessionId:)`**: Get students and current attendance status
- **`markAttendance(...)`**: Mark a student's attendance
- **`syncPending()`**: Push offline records to Supabase

### 📊 Offline Behavior

The app uses `PendingAttendanceStore` (UserDefaults-backed) to queue attendance records:

1. **Online**: Records written directly to Supabase
2. **Offline**: Records saved to local store with `isSynced: false`
3. **Reconnect**: Automatic sync via RPC `sync_attendance()` pushes all pending records
4. **Conflict Resolution**: Server-side logic handles duplicates and conflicts

### 🎨 UI/UX Features

- **Responsive Grid**: Adapts from 3-4 columns based on device orientation
- **Color Coding**: Instant visual feedback for attendance status
- **Status Persistence**: Selection persists on card with visual border
- **Accessibility**: Large buttons suitable for touch interaction
- **Network Awareness**: Clear offline indicator in toolbar

### 🔐 Security Considerations

- Supabase RLS policies enforce role-based data access
- Service role key never shipped in app (anon key only)
- All API calls authenticated via Supabase Auth
- Audit trails maintained on server for all changes

### 🧪 Testing Credentials

```
Role   | Email           | Password
-------|-----------------|----------
Tutor  | tutor@tava.dev  | TAVAdev123!
Admin  | admin@tava.dev  | TAVAdev123!
Parent | parent@tava.dev | TAVAdev123!
```

## Next Steps (Phase 2 & 3)

- **Communication Module**: In-app messaging and announcements
- **Results Management**: Digital result slips and progress tracking
- **Safety Features**: Dismissal tracking and safe arrival notifications
- **Analytics**: Attendance reports and insights

## Development Notes

- The app uses the cloud Supabase instance (not local Docker)
- Update `SupabaseManager.swift` with correct cloud credentials
- Supabase Swift SDK (v2.0+) handles Auth, Realtime, and PostgREST
- Network monitoring uses Apple's Network framework
- No third-party UI libraries required (pure SwiftUI)

## Troubleshooting

### Issue: Can't sign in
- Verify Supabase credentials in `SupabaseManager.swift`
- Check that user exists in Supabase (see test credentials above)
- Ensure Network is connected

### Issue: Classes not loading
- Verify user role in Supabase `profiles` table
- Check RLS policies in `002_rls.sql`
- Ensure class assignments exist in `class_assignments` table

### Issue: Offline sync not working
- Check network reconnection detection in `NetworkMonitor.swift`
- Verify pending records in UserDefaults
- Check `sync_attendance()` RPC in `003_functions_triggers.sql`

## Performance Optimizations

- Grid layout caches rendered cells efficiently
- Roster entries use ID-based identity for SwiftUI optimization
- Network requests are debounced to prevent duplicate API calls
- Offline queue is checked before showing sync button
