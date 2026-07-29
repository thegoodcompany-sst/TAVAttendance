import LocalAuthentication
import SwiftUI

struct KioskSettingsSheet: View {
    @Binding var storedPIN: String
    @Binding var isLocked: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showPINSetup = false
    @AppStorage("kioskBiometricUnlock") private var kioskBiometricUnlock = false

    // SECURITY: Change PIN / Remove PIN both re-authenticate against the current PIN
    // before taking effect, so reaching this sheet is not enough to alter the PIN.
    private enum SecureAction { case change, remove }
    @State private var challenge: SecureAction? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        if storedPIN.isEmpty {
                            Label("No PIN set — kiosk is unlocked", systemImage: "lock.open")
                                .foregroundStyle(.secondary)
                            Button("Set Kiosk PIN…") { showPINSetup = true }
                        } else {
                            Label("PIN configured", systemImage: "lock.fill")
                                .foregroundStyle(.green)
                            Button("Change PIN…") { challenge = .change }
                            Button("Lock Kiosk Now") {
                                isLocked = true
                                dismiss()
                            }
                            Button("Remove PIN", role: .destructive) {
                                challenge = .remove
                            }
                        }
                    } header: {
                        Text("Kiosk Lock")
                    } footer: {
                        Text("When locked the tab bar is hidden and only the sign-in grid is shown. Tap the lock icon and enter the PIN to unlock and access admin controls.")
                    }

                    if !storedPIN.isEmpty,
                       let name = Biometrics.biometryName(policy: .deviceOwnerAuthenticationWithBiometrics) {
                        Section {
                            Toggle("Allow \(name) Unlock", isOn: $kioskBiometricUnlock)
                        } footer: {
                            Text("Anyone enrolled in \(name) on this iPad can unlock admin mode. Enable only if this device's \(name) is staff-only. The PIN always remains available.")
                        }
                    }
                }

                // Re-authentication overlay for the destructive PIN actions.
                if let action = challenge {
                    // Recovery is intentionally unavailable here. Changing/removing a valid
                    // PIN still requires that PIN; the device-owner reset path lives only on
                    // the locked kiosk recovery screen.
                    PINUnlockOverlay(storedPIN: storedPIN) { success in
                        challenge = nil
                        guard success else { return }
                        switch action {
                        case .change: showPINSetup = true
                        case .remove: storedPIN = ""; isLocked = false
                        }
                    }
                    .zIndex(10)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Kiosk Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPINSetup) {
                PINSetupSheet(storedPIN: $storedPIN)
            }
        }
    }
}

// MARK: - PIN setup (custom number pad)

struct PINSetupSheet: View {
    @Binding var storedPIN: String
    @Environment(\.dismiss) private var dismiss

    @State private var firstPIN = ""
    @State private var secondPIN = ""
    @State private var step = 1
    @State private var error = ""

    private var current: String { step == 1 ? firstPIN : secondPIN }

    var body: some View {
        NavigationStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
                .overlay(
                    VStack(spacing: 40) {
                        Spacer()

                        VStack(spacing: 16) {
                            Text(step == 1 ? "Choose a 4-digit PIN" : "Confirm your PIN")
                                .font(.title2.bold())

                            HStack(spacing: 20) {
                                ForEach(0..<4) { i in
                                    Circle()
                                        .fill(current.count > i ? Color.accentColor : Color(.systemGray4))
                                        .frame(width: 18, height: 18)
                                }
                            }

                            if !error.isEmpty {
                                Text(error).foregroundStyle(.red).font(.subheadline)
                            }
                        }

                        numPad(tint: .accentColor) { digit in append(digit) } onDelete: { deleteLast() }

                        Spacer()
                    }
                    .padding(32)
                )
            .navigationTitle(storedPIN.isEmpty ? "Set PIN" : "Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func append(_ d: String) {
        error = ""
        if step == 1 {
            guard firstPIN.count < 4 else { return }
            firstPIN += d
            if firstPIN.count == 4 { step = 2 }
        } else {
            guard secondPIN.count < 4 else { return }
            secondPIN += d
            if secondPIN.count == 4 { confirm() }
        }
    }

    private func deleteLast() {
        error = ""
        if step == 2 { if secondPIN.isEmpty { step = 1 } else { secondPIN.removeLast() } }
        else if !firstPIN.isEmpty { firstPIN.removeLast() }
    }

    private func confirm() {
        if firstPIN == secondPIN { storedPIN = hashPIN(firstPIN); dismiss() }
        else { error = "PINs don't match — try again"; firstPIN = ""; secondPIN = ""; step = 1 }
    }
}

// MARK: - PIN unlock overlay

struct PINUnlockOverlay: View {
    let storedPIN: String
    // Recovery returns true only after the caller has authenticated the device owner.
    // Keeping the result async prevents the overlay from clearing lockout counters before
    // LocalAuthentication has actually succeeded.
    var onReset: (() async -> Bool)? = nil
    var recoveryRequired = false
    // Kiosk-settings opt-in: offers Face ID/Touch ID as an alternative door. Success
    // does not touch the PIN failure counters — it's simply another way in.
    var allowBiometric = false
    let onDone: (Bool) -> Void

    // Persisted so a device restart can't reset the lockout counter.
    @AppStorage("kioskFailedAttempts") private var failedAttempts: Int = 0
    @AppStorage("kioskLockoutUntil") private var lockoutUntil: Double = 0

    @State private var entered = ""
    @State private var error = ""
    @State private var secondsRemaining: Int = 0
    @State private var isResetting = false

    private var isLockedOut: Bool {
        isKioskUnlockBlocked(lockoutUntil: lockoutUntil, now: Date().timeIntervalSince1970)
    }

    private var lockoutMessage: String {
        let s = secondsRemaining
        if s >= 60 { return "Try again in \(s / 60)m \(s % 60)s" }
        return "Try again in \(s)s"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                    Text("Admin Access")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text(recoveryRequired
                         ? "Saved PIN needs secure recovery"
                         : (isLockedOut ? "Too many attempts" : "Enter PIN to unlock"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if recoveryRequired {
                    VStack(spacing: 16) {
                        Text("Authenticate with the device passcode or biometrics to reset this damaged PIN.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                        authenticatedResetButton("Reset with Device Authentication")
                        Button("Cancel") { onDone(false) }
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else if isLockedOut {
                    VStack(spacing: 12) {
                        Text(lockoutMessage)
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                        Button("Cancel") { onDone(false) }
                            .foregroundStyle(.white.opacity(0.7))
                        authenticatedResetButton("Forgot PIN — Reset Kiosk")
                            .padding(.top, 8)
                    }
                } else {
                    HStack(spacing: 20) {
                        ForEach(0..<4) { i in
                            Circle()
                                .fill(entered.count > i ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 18, height: 18)
                        }
                    }

                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }

                    numPad(tint: .white,
                           onDigit: { digit in appendUnlock(digit) },
                           onDelete: { if !entered.isEmpty { entered.removeLast() } },
                           leading: { AnyView(
                               Button("Cancel") { onDone(false) }
                                   .foregroundStyle(.white.opacity(0.7))
                                   .frame(width: 80, height: 80)
                           ) })

                    // No auto-prompt: the overlay can be opened accidentally by a student,
                    // so biometrics require an explicit tap.
                    if allowBiometric,
                       let name = Biometrics.biometryName(policy: .deviceOwnerAuthenticationWithBiometrics) {
                        Button {
                            Task {
                                if await Biometrics.authenticate(
                                    reason: "Unlock kiosk admin mode",
                                    policy: .deviceOwnerAuthenticationWithBiometrics) {
                                    onDone(true)
                                }
                            }
                        } label: {
                            Label("Unlock with \(name)",
                                  systemImage: name == "Touch ID" ? "touchid" : "faceid")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(48)
        }
        .onAppear { tick() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in tick() }
    }

    private func tick() {
        let remaining = lockoutUntil - Date().timeIntervalSince1970
        secondsRemaining = remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    @ViewBuilder
    private func authenticatedResetButton(_ title: String) -> some View {
        if let onReset {
            Button(title, role: .destructive) {
                isResetting = true
                Task {
                    let didReset = await onReset()
                    if didReset {
                        failedAttempts = 0
                        lockoutUntil = 0
                    }
                    isResetting = false
                }
            }
            .foregroundStyle(.red)
            .disabled(isResetting)
        }
    }

    private func appendUnlock(_ d: String) {
        guard !isLockedOut, entered.count < 4 else { return }
        error = ""
        entered += d
        if entered.count == 4 {
            let now = Date().timeIntervalSince1970
            let current = KioskPINLockoutState(
                failedAttempts: failedAttempts,
                lockoutUntil: lockoutUntil
            )
            // Constant-time compare of the derived hash (not the short PIN itself).
            let matches = kioskPINMatches(entered: entered, storedPIN: storedPIN)
            let (next, result) = evaluateKioskPINAttempt(
                pinMatches: matches,
                state: current,
                now: now
            )
            failedAttempts = next.failedAttempts
            lockoutUntil = next.lockoutUntil
            switch result {
            case .unlocked:
                onDone(true)
            case .lockedOut:
                // Exponential backoff grows with total failures; the counter is left
                // in place so the next wrong entry after the lockout locks longer.
                tick()
                entered = ""
            case .incorrect(let attemptsLeft):
                error = "Incorrect PIN — \(attemptsLeft) attempt\(attemptsLeft == 1 ? "" : "s") left"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { entered = ""; error = "" }
            }
        }
    }
}
func numPad(
    tint: Color,
    onDigit: @escaping (String) -> Void,
    onDelete: @escaping () -> Void,
    leading: (() -> AnyView)? = nil
) -> some View {
    let rows: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"]]
    return VStack(spacing: 16) {
        ForEach(rows.indices, id: \.self) { i in
            HStack(spacing: 16) {
                ForEach(rows[i], id: \.self) { d in
                    padKey(d, tint: tint, action: { onDigit(d) })
                }
            }
        }
        HStack(spacing: 16) {
            if let l = leading {
                l()
            } else {
                Spacer().frame(width: 80, height: 80)
            }
            padKey("0", tint: tint, action: { onDigit("0") })
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        }
    }
}

func padKey(_ digit: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(digit)
            .font(.title.weight(.light))
            .frame(width: 80, height: 80)
            .background(tint.opacity(tint == .white ? 0.15 : 0.1), in: Circle())
            .foregroundStyle(tint == .white ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
}
