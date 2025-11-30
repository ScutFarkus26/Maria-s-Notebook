// StudentDetailView.swift
// A focused sheet for displaying a student's details and upcoming lessons

import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false

    @State private var nextLessonsForStudent: [StudentLesson] = []
    @State private var lessonsByID: [UUID: Lesson] = [:]
    @State private var isLoadingLessons = true

    // MARK: - Derived
    private var levelColor: Color {
        switch student.level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    private var formattedBirthday: String {
        return Self.birthdayFormatter.string(from: student.birthday)
    }

    private var ageDescription: String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: student.birthday, to: Date())
        let years = comps.year ?? 0
        if years <= 0 { return "Less than 1 year old" }
        if years == 1 { return "1 year old" }
        return "\(years) years old"
    }

    private var initials: String {
        let parts = student.fullName.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let last = parts.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        } else if let first = student.fullName.first {
            return String(first).uppercased()
        } else {
            return "?"
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Student Info")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    headerContent
                        .padding(.top, 36)

                    if isEditing {
                        editForm
                    } else {
                        infoRows

                        Divider()
                            .padding(.top, 8)

                        nextLessonsSection
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .task(id: student.id) {
            await loadStudentData()
        }
        .alert("Delete Student?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(student)
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Subviews
    private var headerContent: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.purple, Color.pink]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.pink.opacity(0.25), radius: 24, x: 0, y: 10)

                Text(initials)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))

            Text(student.level.rawValue)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(levelColor.opacity(0.12)))
        }
        .frame(maxWidth: .infinity)
    }

    private var infoRows: some View {
        VStack(spacing: 14) {
            infoRow(icon: "calendar", title: "Birthday", value: formattedBirthday)
            if let ds = student.dateStarted {
                infoRow(icon: "calendar.badge.clock", title: "Start Date", value: Self.birthdayFormatter.string(from: ds))
            }
            infoRow(icon: "gift", title: "Age", value: ageDescription)
            infoRow(icon: "graduationcap", title: "Florida Grade Equivalent", value: FloridaGradeCalculator.grade(for: student.birthday).displayString)
        }
        .padding(.horizontal, 8)
    }

    private var editForm: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("First Name", text: $draftFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Last Name", text: $draftLastName)
                    .textFieldStyle(.roundedBorder)
            }
            DatePicker("Birthday", selection: $draftBirthday, displayedComponents: .date)
            DatePicker("Start Date", selection: $draftStartDate, displayedComponents: .date)
            Picker("Level", selection: $draftLevel) {
                Text(Student.Level.lower.rawValue).tag(Student.Level.lower)
                Text(Student.Level.upper.rawValue).tag(Student.Level.upper)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 8)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
        }
    }

    private func lessonName(for sl: StudentLesson) -> String {
        return lessonsByID[sl.lessonID]?.name ?? "Lesson"
    }

    private func lessonSubject(for sl: StudentLesson) -> String? {
        return lessonsByID[sl.lessonID]?.subject
    }

    private var nextLessonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Lessons")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(nextLessonsForStudent.count)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if isLoadingLessons {
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else if nextLessonsForStudent.isEmpty {
                Text("No lessons scheduled yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(nextLessonsForStudent, id: \.id) { sl in
                        HStack(spacing: 12) {
                            Image(systemName: "book")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lessonName(for: sl))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let subject = lessonSubject(for: sl), !subject.isEmpty {
                                    Text(subject)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                    }
                    Button("Save") {
                        let fn = draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ln = draftLastName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !fn.isEmpty, !ln.isEmpty else { return }
                        student.firstName = fn
                        student.lastName = ln
                        student.birthday = draftBirthday
                        student.level = draftLevel
                        student.dateStarted = draftStartDate
                        try? modelContext.save()
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        draftFirstName = student.firstName
                        draftLastName = student.lastName
                        draftBirthday = student.birthday
                        draftLevel = student.level
                        draftStartDate = student.dateStarted ?? Date()
                        isEditing = true
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteAlert = true
                    }
                    Button("Done") {
                        if let onDone { onDone() } else { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @MainActor
    private func loadStudentData() async {
        isLoadingLessons = true
        defer { isLoadingLessons = false }

        let sid = student.id

        do {
            // Fetch upcoming StudentLesson broadly, then filter in-memory for this student to avoid predicate limitations
            let upcomingDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.givenAt == nil })
            let allUpcoming = try modelContext.fetch(upcomingDescriptor)
            let fetchedSL = allUpcoming.filter { $0.studentIDs.contains(sid) }

            // Sort to match previous logic
            let sortedSL = fetchedSL.sorted { lhs, rhs in
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?):
                    return l < r
                case (nil, nil):
                    return lhs.createdAt < rhs.createdAt
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                }
            }
            nextLessonsForStudent = sortedSL

            // Prefetch only referenced lessons in a single batched fetch and cache them
            let ids = Set(sortedSL.map { $0.lessonID })
            if ids.isEmpty {
                lessonsByID = [:]
            } else {
                do {
                    let lPredicate = #Predicate<Lesson> { lesson in
                        ids.contains(lesson.id)
                    }
                    let lDescriptor = FetchDescriptor<Lesson>(predicate: lPredicate)
                    let lessons = try modelContext.fetch(lDescriptor)
                    lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
                } catch {
                    // Fallback: fetch all lessons and filter in-memory
                    let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                    let filtered = allLessons.filter { ids.contains($0.id) }
                    lessonsByID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
                }
            }
        } catch {
            // If fetch fails, leave arrays empty; UI will show empty state
            nextLessonsForStudent = []
            lessonsByID = [:]
        }
    }

    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    // NOTE: This preview uses placeholders and will need a real Student from your model to render accurately.
    // Creating a lightweight mock to preview layout only.
    struct MockStudent: Hashable {
        var fullName: String
        var birthday: Date
        enum Level: String { case upper = "Upper", lower = "Lower" }
        var level: Level
        var nextLessons: [Int]
    }
    // The preview below is a visual placeholder and not compiled with the app target.
    return Text("StudentDetailView Preview requires app data model.")
}

