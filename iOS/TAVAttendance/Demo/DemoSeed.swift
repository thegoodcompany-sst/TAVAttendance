import Foundation

/// One attendance row inside the on-device demo store.
struct DemoAttendanceRow {
    let id: UUID
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    var markedAt: Date
    var notes: String?
    var lateReason: String?
    var absenceInformed: Bool?
}

struct DemoParentLink: Equatable {
    let parentId: UUID
    let studentId: UUID
}

/// The whole demo dataset. Everything here is invented; no production rows are
/// copied. Student and class IDs match `web/lib/demo/seed.ts`, so QR codes
/// printed from the web demo scan on the iPad demo kiosk.
struct DemoDataset {
    var profiles: [Profile]
    var classes: [TAVClass]
    var students: [Student]
    var enrollments: [Enrollment]
    var assignments: [TutorAssignment]
    var sessions: [Session]
    var attendance: [DemoAttendanceRow]
    var results: [StudentResult]
    var resultSlips: [ResultSlip]
    var messages: [ParentMessage]
    var dismissals: [Dismissal]
    var consents: [ConsentRecord]
    var corrections: [CorrectionRequest]
    var parentLinks: [DemoParentLink]
    var privacyNotice: PolicyDocument
}

enum DemoSeed {
    // MARK: - Stable identifiers

    enum Kind: Int {
        case profile = 1, schoolClass, student, enrollment, assignment, session,
             attendance, result, resultSlip, message, correction, dismissal
    }

    static func id(_ kind: Kind, _ n: Int) -> UUID {
        let text = String(format: "de%06lx-0000-4000-8000-%012lx", kind.rawValue, n)
        return UUID(uuidString: text)!
    }

    static let adminId = DemoMode.userId
    static let tutorRachelId = id(.profile, 2)
    static let tutorDanielId = id(.profile, 3)
    static let tutorPriyaId = id(.profile, 4)
    static let parentSitiId = id(.profile, 5)
    static let parentJasonId = id(.profile, 6)

    struct ClassSpec {
        let n: Int
        let name: String
        let subject: String
        let level: String
        let day: String
        let byday: String
        let weekday: Int   // Calendar weekday, Sunday = 1
        let tutors: [UUID]
    }

    static let classSpecs: [ClassSpec] = [
        ClassSpec(n: 1, name: "P5 English", subject: "English", level: "P5", day: "Monday",
                  byday: "MO", weekday: 2, tutors: [tutorRachelId, tutorPriyaId]),
        ClassSpec(n: 2, name: "P6 Mathematics", subject: "Math", level: "P6", day: "Thursday",
                  byday: "TH", weekday: 5, tutors: [tutorDanielId, tutorPriyaId]),
        ClassSpec(n: 3, name: "Sec 1 English", subject: "English", level: "Sec 1", day: "Monday",
                  byday: "MO", weekday: 2, tutors: [tutorRachelId]),
        ClassSpec(n: 4, name: "Sec 2 Mathematics", subject: "Math", level: "Sec 2", day: "Thursday",
                  byday: "TH", weekday: 5, tutors: [tutorDanielId]),
    ]

    struct StudentSpec {
        let n: Int
        let name: String
        let school: String
        let year: String
        let classN: Int
    }

    /// Invented roster. Four familiar names carry Easter eggs (see DemoEasterEgg).
    static let studentSpecs: [StudentSpec] = [
        StudentSpec(n: 1, name: "Nick Chan", school: "Bukit View Primary", year: "P5", classN: 1),
        StudentSpec(n: 2, name: "Aisyah Binte Rahim", school: "Keming Primary", year: "P5", classN: 1),
        StudentSpec(n: 3, name: "Ethan Lim Jun Hao", school: "Dazhong Primary", year: "P5", classN: 1),
        StudentSpec(n: 4, name: "Kavya Raj", school: "Bukit View Primary", year: "P5", classN: 1),
        StudentSpec(n: 5, name: "Ryan Teo", school: "Lianhua Primary", year: "P5", classN: 1),
        StudentSpec(n: 6, name: "Chloe Ng", school: "Keming Primary", year: "P5", classN: 1),
        StudentSpec(n: 7, name: "Lauren Tan", school: "Princess Elizabeth Primary", year: "P6", classN: 2),
        StudentSpec(n: 8, name: "Muhammad Irfan", school: "Dazhong Primary", year: "P6", classN: 2),
        StudentSpec(n: 9, name: "Isabelle Wong", school: "Bukit View Primary", year: "P6", classN: 2),
        StudentSpec(n: 10, name: "Jayden Goh", school: "Keming Primary", year: "P6", classN: 2),
        StudentSpec(n: 11, name: "Nurul Huda", school: "Lianhua Primary", year: "P6", classN: 2),
        StudentSpec(n: 12, name: "Arjun Pillai", school: "Princess Elizabeth Primary", year: "P6", classN: 2),
        StudentSpec(n: 13, name: "Agrim Singh", school: "Bukit Batok Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 14, name: "Megan Lee", school: "Hillgrove Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 15, name: "Darren Ong", school: "Bukit Batok Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 16, name: "Sophia Chua", school: "Swiss Cottage Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 17, name: "Aaliyah Hassan", school: "Hillgrove Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 18, name: "Caleb Seah", school: "Bukit Batok Secondary", year: "Sec 1", classN: 3),
        StudentSpec(n: 19, name: "Brian Chew", school: "Swiss Cottage Secondary", year: "Sec 2", classN: 4),
        StudentSpec(n: 20, name: "Marcus Yeo", school: "Hillgrove Secondary", year: "Sec 2", classN: 4),
        StudentSpec(n: 21, name: "Tan Hui Min", school: "Bukit Batok Secondary", year: "Sec 2", classN: 4),
        StudentSpec(n: 22, name: "Zachary Lau", school: "Swiss Cottage Secondary", year: "Sec 2", classN: 4),
        StudentSpec(n: 23, name: "Natalie Ho", school: "Hillgrove Secondary", year: "Sec 2", classN: 4),
        StudentSpec(n: 24, name: "Javier Toh", school: "Bukit Batok Secondary", year: "Sec 2", classN: 4),
    ]

    static let pastWeeks = 8

    static let sessionNotes = [
        "Great energy tonight. Dinner was fried bee hoon.",
        "Revision for the upcoming test; most finished the worksheet.",
        "Reading circle went well. Two kids volunteered to read aloud.",
        "Heavy rain, a few arrived late.",
    ]

    /// Deterministic attendance for past sessions: mostly present, some late,
    /// a few absent. Lauren Tan keeps a perfect record.
    static func pastStatus(studentN: Int, sessionIndex: Int, name: String) -> (AttendanceStatus, Bool?, Int) {
        let v = (studentN * 37 + sessionIndex * 53 + 11) % 100
        if name == "Lauren Tan" { return (.present, nil, v) }
        if v < 8 { return (.absent, v % 2 == 0, v) }
        if v < 18 { return (.late, nil, v) }
        return (.present, nil, v)
    }

    static func grade(studentN: Int, subject: String, year: String, name: String) -> String {
        let primary = year.hasPrefix("P")
        if name == "Lauren Tan" { return primary ? "AL1" : "A1" }
        let bands = primary ? GradeBands.primary : GradeBands.secondary
        let idx = (studentN * 7 + (subject == "Math" ? 3 : 1)) % 5
        return bands[idx]
    }

    // MARK: - Build

    static func make(now: Date = Date()) -> DemoDataset {
        let cal = AttendanceService.singaporeCalendar
        let ymd = AttendanceService.ymdFormatter
        let today = cal.startOfDay(for: now)
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let profiles: [Profile] = [
            DemoMode.profile,
            Profile(id: tutorRachelId, fullName: "Rachel Lim", role: "tutor", phone: nil),
            Profile(id: tutorDanielId, fullName: "Daniel Koh", role: "tutor", phone: nil),
            Profile(id: tutorPriyaId, fullName: "Priya Nair", role: "tutor", phone: nil),
            Profile(id: parentSitiId, fullName: "Siti Rahman", role: "parent", phone: nil),
            Profile(id: parentJasonId, fullName: "Jason Goh", role: "parent", phone: nil),
        ]

        var classes: [TAVClass] = classSpecs.map { spec in
            TAVClass(
                id: id(.schoolClass, spec.n), name: spec.name, subject: spec.subject,
                level: spec.level, scheduleDay: spec.day, scheduleTime: "19:00:00",
                durationMinutes: 120, isActive: true,
                recurrenceRule: "FREQ=WEEKLY;BYDAY=\(spec.byday)", recurrenceEndDate: nil,
                isStudySpace: false, canManageSessions: true, canOperateTodaySession: true)
        }
        classes.append(TAVClass(
            id: AttendanceService.studySpaceClassId, name: "Study Space", subject: nil,
            level: nil, scheduleDay: nil, scheduleTime: nil, durationMinutes: 120,
            isActive: true, recurrenceRule: nil, recurrenceEndDate: nil,
            isStudySpace: true, canManageSessions: true, canOperateTodaySession: true))

        let students: [Student] = studentSpecs.map {
            Student(id: id(.student, $0.n), fullName: $0.name, school: $0.school,
                    yearOfStudy: $0.year, isActive: true, avatarUrl: nil)
        }

        let enrollments: [Enrollment] = studentSpecs.map {
            Enrollment(id: id(.enrollment, $0.n), studentId: id(.student, $0.n),
                       classId: id(.schoolClass, $0.classN), isActive: true)
        }

        var assignments: [TutorAssignment] = []
        for spec in classSpecs {
            for tutor in spec.tutors {
                assignments.append(TutorAssignment(
                    id: id(.assignment, assignments.count + 1),
                    classId: id(.schoolClass, spec.n), tutorId: tutor))
            }
        }

        var sessions: [Session] = []
        var attendance: [DemoAttendanceRow] = []

        for spec in classSpecs {
            let classId = id(.schoolClass, spec.n)
            let roster = studentSpecs.filter { $0.classN == spec.n }

            // Most recent matching weekday strictly before today, then weekly back.
            var latest = cal.date(byAdding: .day, value: -1, to: today) ?? today
            while cal.component(.weekday, from: latest) != spec.weekday {
                latest = cal.date(byAdding: .day, value: -1, to: latest) ?? latest
            }
            for week in 0..<pastWeeks {
                guard let day = cal.date(byAdding: .day, value: -7 * week, to: latest) else { continue }
                let sessionId = id(.session, spec.n * 100 + week + 1)
                let note: String? = week % 3 == 0 ? sessionNotes[(spec.n + week) % sessionNotes.count] : nil
                sessions.append(Session(
                    id: sessionId, classId: classId, sessionDate: ymd.string(from: day),
                    topic: nil, notes: note, startedAt: at(day, 19, 0), endedAt: at(day, 21, 0),
                    subTutorId: nil))
                for student in roster {
                    let (status, informed, v) = pastStatus(
                        studentN: student.n, sessionIndex: spec.n * 10 + week, name: student.name)
                    let markedAt: Date
                    switch status {
                    case .present: markedAt = at(day, 18, 40 + v % 20)
                    case .late: markedAt = at(day, 19, 5 + v % 25)
                    case .absent: markedAt = at(day, 19, 45)
                    }
                    attendance.append(DemoAttendanceRow(
                        id: id(.attendance, attendance.count + 1), sessionId: sessionId,
                        studentId: id(.student, student.n), status: status, markedAt: markedAt,
                        notes: nil,
                        lateReason: status == .late ? (v % 2 == 0 ? "Bus was late" : "School CCA ran over") : nil,
                        absenceInformed: status == .absent ? informed : nil))
                }
            }

            // Today's session, open and not yet started, so the demo can run a live roll call.
            let todayId = id(.session, spec.n * 100)
            sessions.append(Session(
                id: todayId, classId: classId, sessionDate: ymd.string(from: today),
                topic: nil, notes: nil, startedAt: nil, endedAt: nil, subTutorId: nil))
        }

        // A couple of early arrivals today so the boards don't start empty.
        let earlyArrivals: [(studentN: Int, classN: Int, minutesAgo: Double)] = [
            (2, 1, 25), (3, 1, 18), (14, 3, 12),
        ]
        for arrival in earlyArrivals {
            attendance.append(DemoAttendanceRow(
                id: id(.attendance, attendance.count + 1),
                sessionId: id(.session, arrival.classN * 100),
                studentId: id(.student, arrival.studentN), status: .present,
                markedAt: now.addingTimeInterval(-arrival.minutesAgo * 60),
                notes: nil, lateReason: nil, absenceInformed: nil))
        }

        var results: [StudentResult] = []
        for spec in studentSpecs {
            for subject in ["Math", "English"] {
                results.append(StudentResult(
                    id: id(.result, results.count + 1), studentId: id(.student, spec.n),
                    subject: subject,
                    grade: grade(studentN: spec.n, subject: subject, year: spec.year, name: spec.name)))
            }
        }

        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now) ?? now }

        let resultSlips: [ResultSlip] = [
            ResultSlip(id: id(.resultSlip, 1), studentId: id(.student, 7), examName: "SA1 Mathematics",
                       examDate: ymd.string(from: daysAgo(40)), subject: "Math", score: 34, maxScore: 35,
                       uploadedAt: daysAgo(38), acknowledgedAt: daysAgo(37)),
            ResultSlip(id: id(.resultSlip, 2), studentId: id(.student, 1), examName: "WA2 English",
                       examDate: ymd.string(from: daysAgo(20)), subject: "English", score: 27, maxScore: 30,
                       uploadedAt: daysAgo(19), acknowledgedAt: nil),
            ResultSlip(id: id(.resultSlip, 3), studentId: id(.student, 19), examName: "Mid-year Mathematics",
                       examDate: ymd.string(from: daysAgo(60)), subject: "Math", score: 78, maxScore: 100,
                       uploadedAt: daysAgo(58), acknowledgedAt: daysAgo(55)),
            ResultSlip(id: id(.resultSlip, 4), studentId: id(.student, 2), examName: "WA2 English",
                       examDate: ymd.string(from: daysAgo(21)), subject: "English", score: 24, maxScore: 30,
                       uploadedAt: daysAgo(18), acknowledgedAt: nil),
        ]

        let messages: [ParentMessage] = [
            ParentMessage(id: id(.message, 1), senderId: parentSitiId, recipientId: nil,
                          studentId: id(.student, 2), subject: "Running late on Monday",
                          body: "Hi teacher, Aisyah will be about 15 minutes late on Monday because of a dentist appointment. Thank you!",
                          sentAt: daysAgo(3), readAt: daysAgo(2), parentOrigin: true),
            ParentMessage(id: id(.message, 2), senderId: adminId, recipientId: parentSitiId,
                          studentId: id(.student, 2), subject: "Re: Running late on Monday",
                          body: "Noted, thanks Mdm Siti! We'll save her a seat and keep dinner for her.",
                          sentAt: daysAgo(2), readAt: daysAgo(2), parentOrigin: false),
            ParentMessage(id: id(.message, 3), senderId: parentJasonId, recipientId: nil,
                          studentId: id(.student, 10), subject: "Dinner on Thursday",
                          body: "Hello! Can Jayden bring his own dinner on Thursday? He is avoiding peanuts for now.",
                          sentAt: daysAgo(1), readAt: nil, parentOrigin: true),
        ]

        let consents: [ConsentRecord] = studentSpecs.map {
            ConsentRecord(studentId: id(.student, $0.n), consentType: "data_collection",
                          status: .granted, method: "paper_form", noticeVersion: "1.1",
                          grantedBy: adminId, parentId: nil, createdAt: daysAgo(90))
        }

        let corrections: [CorrectionRequest] = [
            CorrectionRequest(id: id(.correction, 1), studentId: id(.student, 5), requestedBy: parentJasonId,
                              fieldName: "school", currentValue: "Lianhua Primary",
                              requestedValue: "Lianhua Primary School", status: .pending,
                              reviewedBy: nil, reviewedAt: nil, reviewNote: nil, createdAt: daysAgo(2)),
        ]

        let notice = PolicyDocument(
            id: UUID(uuidString: "de00000d-0000-4000-8000-000000000001")!,
            docType: "data_protection_notice", version: "1.1",
            title: "TAVA Attendance — Data Protection Notice (demo)",
            body: """
            This is demo mode. Everything you see is invented sample data stored only on this device.

            In the real app, TAVA collects each child's name, school, level, and attendance so tutors can account for every child, contact parents when needed, and keep the centre safe. Data is kept only as long as it is needed and is never sold or shared for marketing.
            """,
            isCurrent: true, publishedAt: daysAgo(120))

        return DemoDataset(
            profiles: profiles, classes: classes, students: students,
            enrollments: enrollments, assignments: assignments, sessions: sessions,
            attendance: attendance, results: results, resultSlips: resultSlips,
            messages: messages, dismissals: [], consents: consents,
            corrections: corrections,
            parentLinks: [
                DemoParentLink(parentId: parentSitiId, studentId: id(.student, 2)),
                DemoParentLink(parentId: parentJasonId, studentId: id(.student, 10)),
            ],
            privacyNotice: notice)
    }
}
