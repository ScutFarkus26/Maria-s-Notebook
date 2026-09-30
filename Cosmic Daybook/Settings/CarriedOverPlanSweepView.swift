// CarriedOverPlanSweepView.swift
// Settings › School year › New year › "Carried-over year plans": the sweep
// of year-plan entries whose targets fell in a school year that has ended.
//
// Deliberately shaped like the rollover's own carry-over section — a count
// header, Set All, a landing date, a row per child — so the same decision looks
// the same wherever the guide meets it.

import SwiftUI
import CoreData

struct CarriedOverPlanSweepView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @TestStudentVisibility private var testStudents

    @State private var viewModel = CarriedOverPlanSweepViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .choose: choosePhase
                case .done: donePhase
                }
            }
            .navigationTitle("Carried-Over Year Plans")
            .inlineNavigationTitle()
            .toolbar { toolbarContent }
        }
        .onAppear {
            viewModel.load(
                context: viewContext,
                showTestStudents: testStudents.show,
                testStudentNames: testStudents.namesRaw
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch viewModel.phase {
            case .choose: Button("Cancel") { dismiss() }
            case .done: EmptyView()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch viewModel.phase {
            case .choose:
                Button("Apply (\(viewModel.affectedEntries))") {
                    viewModel.apply(context: viewContext)
                }
                .disabled(viewModel.affectedEntries == 0)
            case .done:
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Choose

    @ViewBuilder
    private var choosePhase: some View {
        if viewModel.surveys.isEmpty {
            SettingsEmptyState(
                symbol: "leaf.fill",
                title: "Nothing carried over",
                message: "Every planned year-plan target on the roster falls in this school year."
            )
        } else {
            List {
                Section {
                    setAllRow
                    if viewModel.hasRedateChoice {
                        DatePicker(
                            "Re-date starting",
                            selection: $viewModel.landing,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text(headerText)
                } footer: {
                    Text(footerText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Children") {
                    ForEach(viewModel.surveys) { survey in
                        childRow(survey)
                    }
                }
            }
        }
    }

    private var setAllRow: some View {
        HStack {
            Text("Every child")
            Spacer()
            Menu {
                choiceButtons { viewModel.setAll($0) }
            } label: {
                Label("Set All", systemImage: "checklist")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func childRow(_ survey: YearPlanCarryOver.Survey) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(survey.name)
                Text(survey.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                choiceButtons { viewModel.setChoice($0, for: survey.studentID) }
            } label: {
                choiceLabel(viewModel.choice(for: survey.studentID))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func choiceButtons(onSelect: @escaping (YearPlanCarryOverChoice) -> Void) -> some View {
        ForEach(YearPlanCarryOverChoice.allCases, id: \.self) { choice in
            Button(choice.label) { onSelect(choice) }
        }
    }

    private func choiceLabel(_ choice: YearPlanCarryOverChoice) -> some View {
        HStack(spacing: AppTheme.Spacing.xsmall) {
            Text(choice.label)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .font(AppTheme.ScaledFont.captionSemibold)
        .foregroundStyle(choice == .leave ? Color.secondary : Color.accentColor)
    }

    private var headerText: String {
        let entries = viewModel.totalEntries
        let children = viewModel.surveys.count
        return "\(entries) \(entries == 1 ? "entry" : "entries") for \(children) "
            + "\(children == 1 ? "child" : "children")"
    }

    private var footerText: String {
        let start = DateFormatters.mediumDate.string(from: viewModel.yearStart)
        return "These targets fall before \(start), when this school year began: last year's intentions, "
            + "not lessons the children have fallen behind on. Re-dating keeps each child's order and the "
            + "spacing between her targets, and skipping never deletes."
    }

    // MARK: - Done

    private var donePhase: some View {
        List {
            Section {
                Label {
                    Text(viewModel.receipt)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                }
            }
        }
    }
}

#Preview {
    CarriedOverPlanSweepViewPreview()
}

private struct CarriedOverPlanSweepViewPreview: View {
    var body: some View {
        CarriedOverPlanSweepView()
    }
}
