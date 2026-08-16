// SchoolYearRolloverView.swift
// Guided school-year rollover sheet: assign per-student outcomes, review the
// summary, apply atomically, then offer PDF summaries for departing students.

import SwiftUI
import CoreData

struct SchoolYearRolloverView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: CDStudent.sortByName,
        predicate: CDStudent.enrolledPredicate
    )
    private var enrolledStudents: FetchedResults<CDStudent>

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var viewModel = SchoolYearRolloverViewModel()
    @State private var reportStudent: CDStudent?

    private var store: SchoolYearStore { dependencies.schoolYearStore }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .assign: assignPhase
                case .review: reviewPhase
                case .done: donePhase
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar { toolbarContent }
        }
        .onAppear {
            viewModel.load(
                students: enrolledStudents.visibleRoster(showTest: showTestStudents, testNames: testStudentNamesRaw),
                store: store
            )
        }
        .sheet(item: $reportStudent) { student in
            ReportGeneratorView(student: student)
        }
    }

    private var title: String {
        switch viewModel.phase {
        case .assign: return "School Year Rollover"
        case .review: return "Review Rollover"
        case .done: return "Rollover Applied"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch viewModel.phase {
            case .assign:
                Button("Cancel") { dismiss() }
            case .review:
                Button("Back") { viewModel.phase = .assign }
            case .done:
                EmptyView()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch viewModel.phase {
            case .assign:
                Button("Review…") { viewModel.phase = .review }
                    .disabled(viewModel.changeCount == 0)
            case .review:
                Button("Apply Rollover (\(viewModel.changeCount))") {
                    viewModel.apply(context: viewContext, store: store)
                }
            case .done:
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Assign

    private var assignPhase: some View {
        List {
            Section {
                DatePicker("Effective date", selection: $viewModel.plan.effectiveDate, displayedComponents: .date)
                Toggle("Log an observation for each change", isOn: $viewModel.plan.writeNotes)
            } footer: {
                Text(viewModel.lensFootnote(store: store))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.studentsByLevel, id: \.level) { group in
                Section {
                    ForEach(group.students, id: \.objectID) { student in
                        assignRow(for: student)
                    }
                } header: {
                    HStack {
                        Text(group.level.rawValue)
                        Spacer()
                        bulkMenu(for: group.level)
                    }
                }
            }
        }
    }

    private func assignRow(for student: CDStudent) -> some View {
        HStack {
            Text(student.fullName)
            Spacer()
            outcomeMenu(for: student)
        }
    }

    private func outcomeMenu(for student: CDStudent) -> some View {
        Menu {
            outcomeButtons(currentLevel: student.level) { outcome in
                viewModel.setOutcome(outcome, for: student)
            }
        } label: {
            outcomeLabel(viewModel.outcome(for: student))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func bulkMenu(for level: CDStudent.Level) -> some View {
        Menu {
            outcomeButtons(currentLevel: level) { outcome in
                viewModel.bulkAssign(outcome, toLevel: level)
            }
        } label: {
            Label("Set All", systemImage: "checklist")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The shared outcome choices for a student (or a whole level): stay, promote to
    /// each other level (natural next level first), transfer, withdraw.
    @ViewBuilder
    private func outcomeButtons(
        currentLevel: CDStudent.Level,
        onSelect: @escaping (RolloverOutcome) -> Void
    ) -> some View {
        Button(RolloverOutcome.stay.label) { onSelect(.stay) }
        Divider()
        ForEach(promotionTargets(from: currentLevel), id: \.self) { target in
            Button("Promote to \(target.rawValue)") { onSelect(.promote(to: target)) }
        }
        Divider()
        Button(RolloverOutcome.transfer.label) { onSelect(.transfer) }
        Button(RolloverOutcome.withdraw.label, role: .destructive) { onSelect(.withdraw) }
    }

    /// The natural next level first, then any other levels the teacher might need.
    private func promotionTargets(from level: CDStudent.Level) -> [CDStudent.Level] {
        var targets: [CDStudent.Level] = []
        if let suggested = level.suggestedPromotionTarget {
            targets.append(suggested)
        }
        for other in CDStudent.Level.allCases where other != level && !targets.contains(other) {
            targets.append(other)
        }
        return targets
    }

    private func outcomeLabel(_ outcome: RolloverOutcome) -> some View {
        HStack(spacing: 4) {
            Text(outcome.label)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(AppTheme.ScaledFont.captionSemibold)
        .foregroundStyle(outcomeColor(outcome))
    }

    private func outcomeColor(_ outcome: RolloverOutcome) -> Color {
        switch outcome {
        case .stay: return .secondary
        case .promote: return .accentColor
        case .transfer: return .indigo
        case .withdraw: return .gray
        }
    }

    // MARK: - Review

    private var reviewPhase: some View {
        List {
            Section {
                Label(viewModel.summary.text, systemImage: "person.3.sequence")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                Text("Effective \(DateFormatters.mediumDate.string(from: viewModel.plan.effectiveDate))"
                     + (viewModel.plan.writeNotes ? " · observations will be logged" : ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text(viewModel.lensFootnote(store: store))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            reviewSections
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        ForEach(reviewBuckets, id: \.title) { bucket in
            if !bucket.students.isEmpty {
                Section(bucket.title) {
                    ForEach(bucket.students, id: \.objectID) { student in
                        Text(student.fullName)
                    }
                }
            }
        }
    }

    private var reviewBuckets: [(title: String, students: [CDStudent])] {
        var buckets: [(String, [CDStudent])] = []
        for level in CDStudent.Level.allCases {
            let promoted = viewModel.students(with: .promote(to: level))
            if !promoted.isEmpty {
                buckets.append(("Promote to \(level.rawValue)", promoted))
            }
        }
        buckets.append(("Transfer Out", viewModel.students(with: .transfer)))
        buckets.append(("Withdraw", viewModel.students(with: .withdraw)))
        buckets.append(("Staying", viewModel.students(with: .stay)))
        return buckets
    }

    // MARK: - Done

    private var donePhase: some View {
        List {
            Section {
                Label {
                    Text("Applied \(viewModel.appliedChangeCount) change\(viewModel.appliedChangeCount == 1 ? "" : "s").")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if !viewModel.departingStudents.isEmpty {
                Section {
                    ForEach(viewModel.departingStudents, id: \.objectID) { student in
                        departingRow(for: student)
                    }
                } header: {
                    Text("Departing Students")
                } footer: {
                    Text("Summaries draw from observations flagged \u{201C}Include in report\u{201D} "
                         + "in the outgoing school year. Flag more from a student's Notes tab first if needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func departingRow(for student: CDStudent) -> some View {
        let noteCount = viewModel.flaggedNoteCount(for: student, store: store, context: viewContext)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                Text("\(noteCount) report note\(noteCount == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Generate Summary") { reportStudent = student }
                .buttonStyle(.bordered)
        }
    }
}
