/*
 CompileAudit.swift — One-time scan for “unable to type-check this expression in reasonable time”

 Checklist:
 • Enable the audit by adding -DCOMPILER_AUDIT to: Build Settings → Swift Compiler – Custom Flags → Other Swift Flags (Debug).
 • Build once. Xcode will produce a consolidated batch of diagnostics across the project for heavy expressions.
 • Remove the flag when done. With the flag disabled, this file compiles to nothing and has zero runtime effect.

 Notes:
 • The audit forces the compiler to type-check SwiftUI View bodies by referencing their associated Body types.
 • No code runs at runtime; the references exist only so the compiler performs type-checking during compilation.
 • Add more `audit…()` functions and `touch…` lines as needed to cover additional Views.
*/

#if COMPILER_AUDIT
import SwiftUI

// Helper for views that are hard to construct in audits. Prefer not to instantiate at all.
public protocol PreviewConstructible { static func makeForAudit() -> Self }

// A trivial placeholder View to specialize generic Views when needed.
private struct _AuditDummy: View { var body: some View { EmptyView() } }

// The audit harness. Place references in small, file-scoped functions so this file
// itself remains easy for the compiler to type-check.
struct CompileAudit {
    // Touch only the type to ensure it’s referenced by the compiler.
    private static func touchType<V: View>(_ type: V.Type) { let _ = V.self }
    // Touch the associated Body type to force the compiler to type-check the body expression.
    private static func touchBody<V: View>(_ type: V.Type) { let _ = V.Body.self }

    // MARK: - Forced type-check triggers (non-runtime)
    // Using typealiases to View.Body forces the compiler to resolve the view body type,
    // which triggers type-checking at compile-time without executing any code.

    // PillButton 2.swift
    typealias _Audit_PillNavButton_Body = PillNavButton.Body

    // WorkView.swift
    typealias _Audit_WorkView_Body = WorkView.Body

    // StudentLessonDetailView.swift
    typealias _Audit_StudentLessonDetailView_Body = StudentLessonDetailView.Body

    // LessonProgressSection.swift
    typealias _Audit_LessonProgressSection_Body = LessonProgressSection.Body

    // TodayView.swift
    typealias _Audit_TodayView_Body = TodayView.Body

    // AttendanceView.swift
    typealias _Audit_AttendanceView_Body = AttendanceView.Body

    // WorkDetailView.swift
    typealias _Audit_WorkDetailView_Body = WorkDetailView.Body

    // LessonsRootView.swift
    typealias _Audit_LessonsRootView_Body = LessonsRootView.Body

    // LessonPickerComponents.swift
    typealias _Audit_LessonSection_Body = LessonSection.Body
    typealias _Audit_LessonSearchField_Body = LessonSearchField.Body
    typealias _Audit_LessonPickerPopover_Body = LessonPickerPopover.Body
    typealias _Audit_StudentsSection_Body = StudentsSection.Body
    typealias _Audit_StudentChipsList_Body = StudentChipsList.Body
    typealias _Audit_StatusSection_Body = StatusSection.Body
    typealias _Audit_KeyboardShortcutsOverlay_Body = KeyboardShortcutsOverlay.Body

    // MARK: - Pill Buttons (PillButton 2.swift)
    static func auditPillButtons() {
        touchType(PillNavButton.self)
        touchBody(PillNavButton.self)
    }

    // MARK: - Settings and Admin (SettingsView.swift)
    static func auditSettingsViews() {
        // Top-level views
        touchType(SettingsView.self);              touchBody(SettingsView.self)
        touchType(StatCard.self);                  touchBody(StatCard.self)
        touchType(SectionHeader.self);             touchBody(SectionHeader.self)
        touchType(SettingsCategoryHeader.self);    touchBody(SettingsCategoryHeader.self)
        // Generic container specialized with a trivial content type so the body can be resolved
        typealias _AuditSettingsGroup = SettingsGroup<_AuditDummy>
        touchType(_AuditSettingsGroup.self);       touchBody(_AuditSettingsGroup.self)
        // Subsections
        touchType(SchoolCalendarSettingsView.self); touchBody(SchoolCalendarSettingsView.self)
        touchType(PresentNowSettingsView.self);     touchBody(PresentNowSettingsView.self)
        touchType(LessonAgeSettingsView.self);      touchBody(LessonAgeSettingsView.self)
        touchType(WorkAgeSettingsView.self);        touchBody(WorkAgeSettingsView.self)
    }

    // MARK: - Students Grid (StudentsCardsGridView.swift)
    static func auditStudentsGrid() {
        touchType(StudentsCardsGridView.self)
        touchBody(StudentsCardsGridView.self)
        // Note: Private nested card views are intentionally not referenced here.
    }

    // MARK: - Work (WorkView.swift)
    static func auditWorkView() {
        touchType(WorkView.self)
        touchBody(WorkView.self)
    }

    // MARK: - Student Lesson Detail (StudentLessonDetailView.swift)
    static func auditStudentLessonDetail() {
        touchType(StudentLessonDetailView.self)
        touchBody(StudentLessonDetailView.self)
        touchType(LessonProgressSection.self)
        touchBody(LessonProgressSection.self)
    }

    // MARK: - Today (TodayView.swift)
    static func auditToday() {
        touchType(TodayView.self)
        touchBody(TodayView.self)
    }

    // MARK: - Attendance (AttendanceView.swift)
    static func auditAttendance() {
        touchType(AttendanceView.self)
        touchBody(AttendanceView.self)
    }

    // MARK: - Work Detail (WorkDetailView.swift)
    static func auditWorkDetail() {
        touchType(WorkDetailView.self)
        touchBody(WorkDetailView.self)
    }

    // MARK: - Lessons Root (LessonsRootView.swift)
    static func auditLessonsRoot() {
        touchType(LessonsRootView.self)
        touchBody(LessonsRootView.self)
    }

    // MARK: - Lesson Picker Components (LessonPickerComponents.swift)
    static func auditLessonPickerComponents() {
        touchType(LessonSection.self);            touchBody(LessonSection.self)
        touchType(LessonSearchField.self);        touchBody(LessonSearchField.self)
        touchType(LessonPickerPopover.self);      touchBody(LessonPickerPopover.self)
        touchType(StudentsSection.self);          touchBody(StudentsSection.self)
        touchType(StudentChipsList.self);         touchBody(StudentChipsList.self)
        touchType(StatusSection.self);            touchBody(StatusSection.self)
        touchType(KeyboardShortcutsOverlay.self); touchBody(KeyboardShortcutsOverlay.self)
    }
}

#endif
