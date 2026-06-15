import Foundation

/// Client-side PDPA input-hygiene helpers.
///
/// The database also rejects NRIC/FIN-pattern notes via the `reject_nric_in_notes`
/// trigger (migration 011). This client-side check mirrors that pattern so we can warn
/// the user *before* a save round-trips and gets rejected. The DB remains the source of
/// truth — never rely on this check alone.
enum PDPAValidation {

    /// Singapore NRIC/FIN: a leading letter (S/T/F/G/M), 7 digits, a trailing checksum letter.
    /// Mirrors the server regex `\m[STFGM][0-9]{7}[A-Z]\M` (word-boundary anchored).
    private static let nricRegex = try? NSRegularExpression(
        pattern: "(?i)\\b[STFGM][0-9]{7}[A-Z]\\b")

    /// Returns true if the text appears to contain a Singapore NRIC/FIN.
    static func containsNRIC(_ text: String?) -> Bool {
        guard let text, !text.isEmpty, let regex = nricRegex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Standard inline guidance string shown under free-text notes fields.
    static let sensitiveDataGuidance =
        "Do not enter NRIC/FIN or other sensitive identifiers (e.g. medical details)."
}
