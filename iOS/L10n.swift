import Foundation

/// Lightweight localization helper. Backed by Localizable.strings
/// Usage: `L10n.loading.text`, `L10n.versionFormat.format(version)`
public enum L10n {
    case loading
    case privacy
    case done
    case versionFormat
    case noticeUnavailable
    case noticeLoadFailed

    /// Returns the localized string for the key
    public var text: String {
        NSLocalizedString(self.key, comment: "")
    }

    /// Returns the localized, formatted string with arguments (String(format:))
    public func format(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self.key, comment: ""), arguments: args)
    }

    private var key: String {
        switch self {
        case .loading: return "loading"
        case .privacy: return "privacy"
        case .done: return "done"
        case .versionFormat: return "version_format"
        case .noticeUnavailable: return "notice_unavailable"
        case .noticeLoadFailed: return "notice_load_failed"
        }
    }
}
