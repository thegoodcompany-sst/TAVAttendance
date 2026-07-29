import CommonCrypto
import Foundation
import UIKit

// MARK: - Stored PIN classification

enum StoredKioskPINDisposition: Equatable {
    case none
    case currentHash
    case legacyPlaintext
    case requiresAuthenticatedReset
}

/// Classifies persisted PIN data without changing it. Unknown or damaged values must fail
/// closed and can only be cleared after device-owner authentication.
func storedKioskPINDisposition(_ storedPIN: String) -> StoredKioskPINDisposition {
    guard !storedPIN.isEmpty else { return .none }
    if storedPIN.count == 67,
       storedPIN.hasPrefix("v1:"),
       storedPIN.dropFirst(3).allSatisfy(\.isHexDigit) {
        return .currentHash
    }
    if storedPIN.count == 4, storedPIN.allSatisfy(\.isNumber) {
        return .legacyPlaintext
    }
    return .requiresAuthenticatedReset
}

/// A configured PIN always starts locked. Empty storage leaves the kiosk unlocked (demo mode).
func shouldLockKioskOnStart(storedPIN: String) -> Bool {
    !storedPIN.isEmpty
}

// MARK: - Action authorization

/// Student mode may only use the normal sign-in path. Keep this policy beside the
/// mutation handler so callers cannot rely on button/context-menu visibility alone.
func isKioskActionAuthorized(_ action: GlobalKioskView.KioskAction, isAdminMode: Bool) -> Bool {
    if case .signIn = action { return true }
    return isAdminMode
}

// MARK: - Lockout state machine

/// Cumulative failure counter + absolute lockout deadline (unix seconds).
/// Counter resets only on a correct PIN (never when a lockout window expires).
struct KioskPINLockoutState: Equatable {
    var failedAttempts: Int = 0
    var lockoutUntil: TimeInterval = 0
}

enum KioskPINAttemptResult: Equatable {
    case unlocked
    case incorrect(attemptsRemaining: Int)
    case lockedOut(until: TimeInterval)
}

let kioskAttemptsBeforeLockout = 5

/// Exponential backoff keyed on cumulative failures: 5→30s, 6→1m, 7→2m … capped 1h.
func kioskLockoutDuration(forFailures failures: Int) -> TimeInterval {
    let over = max(0, failures - kioskAttemptsBeforeLockout)
    return min(30.0 * pow(2.0, Double(over)), 3600)
}

func isKioskUnlockBlocked(lockoutUntil: TimeInterval, now: TimeInterval) -> Bool {
    now < lockoutUntil
}

/// Pure lockout transition used by the PIN overlay and unit tests.
/// A live lockout wins even when the supplied PIN matches.
func evaluateKioskPINAttempt(
    pinMatches: Bool,
    state: KioskPINLockoutState,
    now: TimeInterval
) -> (state: KioskPINLockoutState, result: KioskPINAttemptResult) {
    if isKioskUnlockBlocked(lockoutUntil: state.lockoutUntil, now: now) {
        return (state, .lockedOut(until: state.lockoutUntil))
    }
    if pinMatches {
        return (KioskPINLockoutState(), .unlocked)
    }

    let failedAttempts = state.failedAttempts + 1
    let attemptsLeft = kioskAttemptsBeforeLockout - failedAttempts
    if attemptsLeft <= 0 {
        let until = now + kioskLockoutDuration(forFailures: failedAttempts)
        let next = KioskPINLockoutState(failedAttempts: failedAttempts, lockoutUntil: until)
        return (next, .lockedOut(until: until))
    }
    let next = KioskPINLockoutState(failedAttempts: failedAttempts, lockoutUntil: 0)
    return (next, .incorrect(attemptsRemaining: attemptsLeft))
}

// MARK: - PIN hashing

// PBKDF2-SHA256 with 10,000 iterations and a device-tied salt.
// "v1:" prefix distinguishes hashed values from any legacy plaintext.
// The identifierForVendor ties the hash to this device installation,
// making offline brute-force against a UserDefaults dump impractical without
// also knowing the device UUID.
//
// ponytail: DEFERRED (finding 8a) — move the hash + a RANDOM salt to the Keychain.
// Not done here because it can't be build-verified in this environment and a blind
// migration risks bricking live kiosks. The exact migration to implement:
//   1. Generate a random 32-byte salt once; store {salt, hash} as one keychain item
//      under service "sg.tava.kiosk", account "pinHash",
//      accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
//   2. Change hashPIN to take the stored salt (not identifierForVendor) so a device
//      restore no longer changes the salt — the "v1:" hash keeps validating.
//   3. On first launch: if UserDefaults "kioskPIN" holds a "v1:" hash and no keychain
//      item exists, copy it into the keychain (keeping the OLD idfv salt for that
//      migrated value via a "v1:"/"v2:" version tag), THEN remove the UserDefaults key.
//   4. New PINs are written "v2:" (random-salt) only. Keep validating "v1:" during a
//      deprecation window. Do NOT delete the UserDefaults copy until the keychain
//      write is confirmed (read-back) to avoid a half-migration lockout.
// Until then, the device-owner-authenticated reset affordance is the in-app recovery path.
func hashPIN(_ pin: String) -> String {
    let salt = (UIDevice.current.identifierForVendor?.uuidString ?? "tava-kiosk-fallback").utf8
    var derived = [UInt8](repeating: 0, count: 32)
    CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        pin, pin.utf8.count,
        Array(salt), salt.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        10_000,
        &derived, derived.count
    )
    return "v1:" + derived.map { String(format: "%02x", $0) }.joined()
}

/// Constant-time equality for PIN hash strings (mirrors Android MessageDigest.isEqual).
func constantTimeEqualHex(_ left: String, _ right: String) -> Bool {
    let a = Array(left.utf8)
    let b = Array(right.utf8)
    var difference = a.count ^ b.count
    let limit = max(a.count, b.count)
    for index in 0..<limit {
        let leftByte = index < a.count ? a[index] : 0
        let rightByte = index < b.count ? b[index] : 0
        difference |= Int(leftByte ^ rightByte)
    }
    return difference == 0
}

/// Verifies an entered PIN against the stored representation. Supports current v1 hashes only
/// at the comparison boundary (legacy plaintext is migrated before unlock).
func kioskPINMatches(entered: String, storedPIN: String) -> Bool {
    switch storedKioskPINDisposition(storedPIN) {
    case .currentHash:
        return constantTimeEqualHex(hashPIN(entered), storedPIN)
    case .legacyPlaintext:
        // Migration path should re-hash before unlock; still compare closed if reached.
        return constantTimeEqualHex(entered, storedPIN)
    case .none, .requiresAuthenticatedReset:
        return false
    }
}
