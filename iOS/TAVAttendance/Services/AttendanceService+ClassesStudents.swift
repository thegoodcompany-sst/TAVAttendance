import Foundation
import Supabase

extension AttendanceService {
    // MARK: - Classes

    func fetchMyClasses() async throws -> [TAVClass] {
        // The shaped RPC includes current assignments plus recent sessions the
        // caller is explicitly covering as a substitute.
        return try await db.rpc("get_my_classes").execute().value
    }

    func createClass(_ cls: ClassInsert) async throws -> TAVClass {
        return try await db.from("classes").insert(cls).select().single().execute().value
    }

    func updateClass(id: UUID, _ cls: ClassInsert) async throws {
        try await db.from("classes").update(cls).eq("id", value: id).execute()
    }

    func deleteClass(id: UUID) async throws {
        try await db.from("classes").update(["is_active": false]).eq("id", value: id).execute()
    }

    // MARK: - Students

    func fetchAllStudents() async throws -> [Student] {
        return try await db.from("students").select()
            .eq("is_active", value: true).order("full_name")
            .execute().value
    }

    /// Parent-safe projection. Migration 038 removes direct parent SELECT on
    /// `students` so staff-only notes, birth dates, and actor IDs never cross
    /// the Data API boundary.
    func fetchParentChildren() async throws -> [Student] {
        return try await db.rpc("get_parent_children").execute().value
    }

    private struct CreateStudentWithConsentParams: Encodable {
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

    /// Creates the student and mandatory consent ledger row in one DB transaction.
    func createStudentWithConsent(_ student: StudentInsert, sourceNote: String? = nil) async throws -> Student {
        return try await db.rpc(
            "create_student_with_consent",
            params: CreateStudentWithConsentParams(
                fullName: student.fullName,
                school: student.school,
                yearOfStudy: student.yearOfStudy,
                sourceNote: sourceNote
            )
        ).execute().value
    }

    func updateStudent(id: UUID, _ student: StudentInsert) async throws {
        try await db.from("students").update(student).eq("id", value: id).execute()
    }

    func deactivateStudent(id: UUID) async throws {
        try await db.from("students").update(["is_active": false]).eq("id", value: id).execute()
    }

    // MARK: - Student results (migration 023)

    /// RLS scopes rows to the caller: admins see all, tutors only students
    /// enrolled in their assigned classes.
    func fetchStudentResults() async throws -> [StudentResult] {
        return try await db.from("student_results").select().execute().value
    }

    func upsertStudentResult(studentId: UUID, subject: ResultSlipSubject, grade: String) async throws {
        let record = StudentResultUpsert(
            studentId: studentId,
            subject: subject.rawValue,
            grade: grade,
            updatedBy: db.auth.currentSession?.user.id)
        try await db.from("student_results")
            .upsert(record, onConflict: "student_id,subject")
            .execute()
    }

    func deleteStudentResult(studentId: UUID, subject: ResultSlipSubject) async throws {
        try await db.from("student_results").delete()
            .eq("student_id", value: studentId)
            .eq("subject", value: subject.rawValue)
            .execute()
    }

    // MARK: - Enrollments

    func fetchEnrollments(classId: UUID) async throws -> [Enrollment] {
        return try await db.from("enrollments").select()
            .eq("class_id", value: classId).eq("is_active", value: true)
            .execute().value
    }

    func enrollStudent(studentId: UUID, classId: UUID) async throws {
        struct EnrollInsert: Encodable {
            let studentId: UUID; let classId: UUID; let isActive: Bool
            enum CodingKeys: String, CodingKey {
                case studentId = "student_id"; case classId = "class_id"; case isActive = "is_active"
            }
        }
        try await db.from("enrollments")
            .upsert(EnrollInsert(studentId: studentId, classId: classId, isActive: true),
                    onConflict: "student_id,class_id")
            .execute()
    }

    func unenrollStudent(studentId: UUID, classId: UUID) async throws {
        // MAINT-04: record when the unenrolment happened, not just is_active=false.
        struct Unenroll: Encodable {
            let isActive: Bool
            let unenrolledAt: String
            enum CodingKeys: String, CodingKey {
                case isActive = "is_active"
                case unenrolledAt = "unenrolled_at"
            }
        }
        let now = ISO8601DateFormatter().string(from: Date())
        try await db.from("enrollments")
            .update(Unenroll(isActive: false, unenrolledAt: now))
            .eq("student_id", value: studentId).eq("class_id", value: classId)
            .execute()
    }

    // MARK: - Tutor assignments

    func fetchTutors() async throws -> [Profile] {
        return try await db.from("profiles").select()
            .eq("role", value: "tutor").order("full_name")
            .execute().value
    }

    func fetchTutorAssignments(classId: UUID) async throws -> [TutorAssignment] {
        return try await db.from("class_tutor_assignments")
            .select("id, class_id, tutor_id")
            .eq("class_id", value: classId)
            .execute().value
    }

    func assignTutor(tutorId: UUID, classId: UUID, assignedUntil: Date? = nil) async throws {
        // MAINT-05: assigned_until can now be set (an end date for the assignment);
        // tutor_owns_class() honours it (NULL = open-ended). nil omits the column.
        struct AssignInsert: Encodable {
            let classId: UUID; let tutorId: UUID; let assignedUntil: String?
            enum CodingKeys: String, CodingKey {
                case classId = "class_id"; case tutorId = "tutor_id"; case assignedUntil = "assigned_until"
            }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let untilStr = assignedUntil.map { fmt.string(from: $0) }
        try await db.from("class_tutor_assignments")
            .upsert(AssignInsert(classId: classId, tutorId: tutorId, assignedUntil: untilStr), onConflict: "class_id,tutor_id")
            .execute()
    }

    func unassignTutor(tutorId: UUID, classId: UUID) async throws {
        try await db.from("class_tutor_assignments")
            .delete()
            .eq("class_id", value: classId).eq("tutor_id", value: tutorId)
            .execute()
    }

    // MARK: - Bulk student import (#12)

    func bulkCreateStudentsWithConsent(_ rows: [StudentInsert]) async throws -> [Student] {
        var created: [Student] = []
        created.reserveCapacity(rows.count)
        for row in rows {
            created.append(try await createStudentWithConsent(row, sourceNote: "Bulk CSV import"))
        }
        return created
    }

}
