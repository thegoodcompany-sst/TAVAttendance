import SwiftUI

// Separate application and storage domain: no backend credentials or authentication.
@main
struct LayoutLabApp: App {
    var body: some Scene {
        WindowGroup { LayoutLabView() }
    }
}

private struct LayoutLabView: View {
    @State private var pin = ""
    @State private var locked = false
    @State private var settings = false
    @State private var unlock = false
    @State private var recovery = false
    @State private var message = "Local fixtures only"

    var body: some View {
        NavigationStack {
            List {
                Section("PIN controls") {
                    Text(message)
                    Text(pin.isEmpty ? "No PIN configured" : "PIN configured")
                    Button("Kiosk Settings") { settings = true }
                    Button("Unlock PIN") { unlock = true }
                        .disabled(pin.isEmpty)
                    Button("Recovery layout") { recovery = true }
                }
                Section("Attendance card layouts") {
                    ForEach(0..<6) { index in
                        KioskCard(
                            entry: fixture(index), isPending: index == 5,
                            isAdminMode: true, isSelectionMode: false,
                            isSelected: false, showPhoto: false,
                            onAction: { _ in message = "Local card action received" },
                            onToggleSelection: {}
                        )
                    }
                }
            }
            .navigationTitle("TAVA Layout Lab")
            .sheet(isPresented: $settings) {
                KioskSettingsSheet(storedPIN: $pin, isLocked: $locked)
            }
            .overlay {
                if unlock {
                    PINUnlockOverlay(storedPIN: pin) { success in
                        message = success ? "PIN accepted" : "Unlock cancelled"
                        unlock = false
                    }
                }
                if recovery {
                    PINUnlockOverlay(storedPIN: "damaged", recoveryRequired: true) { _ in
                        recovery = false
                    }
                }
            }
        }
    }

    private func fixture(_ index: Int) -> KioskEntry {
        let statuses: [AttendanceStatus?] = [nil, .present, .late, .absent, .present, nil]
        return KioskEntry(
            studentId: UUID(), fullName: "Synthetic Layout Student \(index + 1)",
            status: statuses[index], sessions: [],
            dismissedAt: index == 4 ? Date(timeIntervalSince1970: 0) : nil,
            absenceInformed: index == 3 ? true : nil
        )
    }
}
