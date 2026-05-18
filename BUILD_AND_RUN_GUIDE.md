# TAVA Attendance MVP - Build & Run Guide

## Prerequisites

- Xcode 16+ (with iOS 17+ deployment target)
- macOS Sonoma or later
- Access to Supabase cloud database credentials
- Internet connection (for cloud database)

## Step 1: Configure Supabase Credentials

The app uses a cloud-hosted Supabase instance. You need to update the credentials:

1. **Open** `iOS/TAVAttendance/Core/SupabaseManager.swift`

2. **Replace the placeholder values** with your cloud Supabase credentials:

```swift
static let supabaseURL     = "https://YOUR_PROJECT_REF.supabase.co"
static let supabaseAnonKey = "YOUR_ANON_KEY_HERE"
```

**Where to find these:**
- Go to your Supabase Dashboard
- Navigate to **Settings → API**
- Copy the **Project URL** and **anon public key**

## Step 2: Open the Project

```bash
cd iOS
open TAVAttendance.xcodeproj
```

The project will open in Xcode. If you see build warnings, they will resolve once the Supabase Swift package is resolved.

## Step 3: Select Target and Device

1. **Select the TAVAttendance target** from the top-left dropdown
2. **Select a simulator** (e.g., iPad Pro 12.9" for the best experience with the split-view interface)
3. Or connect a physical iPad

## Step 4: Build the Project

Press **⌘B** to build. This will:
- Download and resolve the Supabase Swift SDK
- Compile all source files
- Link frameworks

**Expected output:**
```
Build complete! (X warnings, 0 errors)
```

## Step 5: Run the App

Press **⌘R** to build and run. The app will:
1. Launch in the simulator or on your device
2. Show the login screen
3. Be ready for sign-in

## Step 6: Sign In and Test

### Test Credentials

| Role           | Email           | Password     |
|----------------|-----------------|--------------|
| Attendance Taker| tutor@tava.dev  | TAVAdev123!  |
| Admin          | admin@tava.dev  | TAVAdev123!  |
| Parent         | parent@tava.dev | TAVAdev123!  |

### Testing Flow

**As Attendance Taker (Tutor):**
1. On the login screen, tap **"Attendance Taker"** (left button)
2. Enter email: `tutor@tava.dev`
3. Enter password: `TAVAdev123!`
4. Tap **Sign In**
5. You should see the **iPad split-view interface**:
   - **Left sidebar**: List of classes
   - **Right detail**: Session controls and attendance grid
6. Tap a class from the sidebar
7. Tap **"Start Today's Class"**
8. Mark attendance by tapping P/A/L/E buttons on student cards
9. Try going offline (toggle network in simulator) and marking attendance
10. Go back online and confirm sync happens automatically

**As Admin:**
1. Select **"Admin"** role on login
2. Sign in with `admin@tava.dev` / `TAVAdev123!`
3. You'll see the traditional class list view
4. Can navigate to sessions and view rosters

**As Parent:**
1. Select **"Parent"** role on login
2. Sign in with `parent@tava.dev` / `TAVAdev123!`
3. You'll see their child's classes and attendance

## Troubleshooting

### Issue: Xcode SourceKit Errors

**Solution:** These clear automatically once the Supabase package resolves. If they persist:
1. Product → Clean Build Folder (⇧⌘K)
2. File → Close Window
3. Reopen the project

### Issue: "Cannot connect to Supabase"

**Causes:**
- Supabase credentials not set correctly
- Invalid URL or anon key
- Network issue

**Solutions:**
1. Verify credentials in `SupabaseManager.swift`
2. Check you're using the **anon key** (not service key)
3. Verify internet connection is working
4. Try in a simulator with network access enabled

### Issue: "No Classes Available"

**Causes:**
- User not properly assigned to classes
- RLS policies preventing data access
- Classes not in database

**Solutions:**
1. Verify test data exists in Supabase
2. Check that tutor user is assigned to classes in `class_assignments` table
3. Verify RLS policies are correctly configured

### Issue: Attendance Not Saving

**Causes:**
- Network issue
- Insufficient permissions (RLS policy blocking)
- Invalid session ID

**Solutions:**
1. Check network connection (look for offline indicator)
2. Verify you're a tutor marking your own class
3. Check Supabase RLS policies in `002_rls.sql`

### Issue: iPad Split View Not Appearing

**Causes:**
- Running on iPhone simulator
- Not signed in as Tutor role
- Xcode needs refresh

**Solutions:**
1. Switch to iPad simulator (iPad Pro recommended)
2. Verify you selected "Attendance Taker" role on login
3. Force refresh: Product → Clean Build Folder, then rebuild

## Device Recommendations

### Optimal Experience
- **iPad Pro 12.9"** (6th gen or later)
- Landscape orientation recommended for split view
- Network connectivity for real-time sync

### Minimum Requirements
- iPad (7th gen or later)
- iPhone 12 or later
- Minimum iOS 17.0

## Network Testing

### Test Offline Mode (iOS Simulator)

1. **Go offline:**
   - **Xcode:** Debug → Simulate Location → (none)
   - Or click the WiFi icon in simulator status bar

2. **Mark attendance offline** - cards will have orange sync indicator

3. **Go back online:**
   - Click WiFi icon again and enable network

4. **Verify sync:**
   - Should see network requests in Xcode network debugger
   - Pending records will sync automatically

## Performance Profiling

To profile the app's performance:

1. **Build with Release configuration:** Product → Scheme → Edit Scheme → Release
2. **Run with Instruments:** ⌘I
3. **Select relevant tools:**
   - Core Data (if using)
   - Network (for API calls)
   - Memory (for usage patterns)

## Xcode Debugging Tips

### See Network Requests
```
Product → Scheme → Edit Scheme → Options → Network Link Conditioner
```

### See Console Output
```
View → Debug Area → Activate Console (⇧⌘C)
```

### Breakpoints
Click line numbers to set breakpoints. Execution pauses, letting you inspect state.

### View Hierarchy
Debug → View Hierarchy (⌘⌥6)

## Building for Distribution

When ready to distribute:

1. **Create App ID** in Apple Developer Portal
2. **Configure signing** in Xcode (Target → Signing & Capabilities)
3. **Archive:** Product → Archive
4. **Upload to TestFlight or App Store**

> Note: Distribution requires membership in Apple Developer Program

## Documentation

Refer to these files for more information:

- **MVP_SUMMARY.md** - Feature overview and architecture
- **IMPLEMENTATION_GUIDE.md** - Detailed implementation notes
- **iOS/README.md** - Original setup instructions

## Next Steps

After confirming the app builds and runs:

1. **Test all three user roles** with provided credentials
2. **Test offline functionality** - mark attendance offline, then reconnect
3. **Review the code** to understand the architecture
4. **Plan Phase 2 features** - messaging, results, safety features

## Questions?

- Check the IMPLEMENTATION_GUIDE.md troubleshooting section
- Review code comments in key files (AttendanceTakerView, AuthManager, AttendanceService)
- Consult Supabase documentation for database questions

---

**Ready to run?** Follow the steps above and launch the app! 🚀
