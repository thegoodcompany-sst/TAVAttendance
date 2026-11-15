import Foundation

/// One policy for UI, RPCs and push. Unknown/missing roles and flags fail closed.
struct TeacherPromptsGate: Equatable {
    var master = false
    var workflowFlag = false
    var pushFlag = false
    var role: String? = nil
    var active = false
    var optedIn = false
    var demo = false

    var staff: Bool { active && (role == "teacher" || role == "admin") }
    var workflow: Bool { master && workflowFlag && staff }
    var push: Bool { workflow && pushFlag && optedIn && !demo }

    static var demoLaunch: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--teacher-prompts-demo")
        #else
        return false
        #endif
    }
    private static let workflowSetting = "TEACHER_PROMPTS_V2_ENABLED"
    private static let hostsSetting = "TEACHER_PROMPTS_APPROVED_HOSTS"

    static var masterEnabled: Bool {
        demoLaunch || (Bundle.main.object(forInfoDictionaryKey: workflowSetting) as? String) == "YES"
    }
    // TODO: HUMANS.md teacher-prompt pilot: approve host + Associated Domains/AASA.
    static var approvedHosts: Set<String> {
        Set((Bundle.main.object(forInfoDictionaryKey: hostsSetting) as? [String]) ?? [])
    }

    enum TokenPath: Equatable { case teacher, parent, ignored }
    /// A v2 teacher can never reach the old parent RPC, even with the master OFF.
    static func tokenPath(master: Bool, role: String?, teacherRequest: Bool) -> TokenPath {
        if master && teacherRequest { return .teacher }
        if role == "teacher" || (master && role != "parent") { return .ignored }
        return .parent
    }
}
