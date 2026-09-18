// RolloverCarryOverSection.swift
// The rollover's "Carried-Over Year Plans" section: per child, what to do with
// the lessons she was pencilled in for in the year now closing.
//
// It sits directly below the effective-date section on the assign step and
// disappears entirely when nobody has any, so a rollover in a class with a
// clean plan looks exactly as it always did.

import SwiftUI
import CoreData

struct RolloverCarryOverSection: View {
    @Bindable var viewModel: SchoolYearRolloverViewModel
    let store: SchoolYearStore

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let surveys = viewModel.carryOverSurvey(context: viewContext)
        if !surveys.isEmpty {
            Section {
                setAllRow(surveys)
                if viewModel.hasRedateChoice {
                    landingPicker
                }
                ForEach(surveys) { survey in
                    childRow(survey)
                }
            } header: {
                Text("Carried-Over Year Plans")
            } footer: {
                Text(footerText(surveys))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rows

    private func setAllRow(_ surveys: [YearPlanCarryOver.Survey]) -> some View {
        HStack {
            Text("Every child")
            Spacer()
            Menu {
                choiceButtons { choice in
                    viewModel.bulkCarryOver(choice, in: surveys)
                }
            } label: {
                Label("Set All", systemImage: "checklist")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var landingPicker: some View {
        DatePicker(
            "Re-date starting",
            selection: Binding(
                get: { viewModel.carryOverLandingDate(store: store, context: viewContext) },
                set: { viewModel.plan.carryOverLanding = $0 }
            ),
            displayedComponents: .date
        )
    }

    private func childRow(_ survey: YearPlanCarryOver.Survey) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(survey.name)
                Text(survey.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                choiceButtons { choice in
                    viewModel.setCarryOver(choice, for: survey.studentID)
                }
            } label: {
                choiceLabel(viewModel.carryOverChoice(for: survey.studentID))
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
        HStack(spacing: 4) {
            Text(choice.label)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(AppTheme.ScaledFont.captionSemibold)
        .foregroundStyle(choice == .leave ? Color.secondary : Color.accentColor)
    }

    // MARK: - Footer

    /// "10 entries for 3 children target dates before Sep 1, 2026 — last year's
    /// intentions, not lessons they have fallen behind on."
    private func footerText(_ surveys: [YearPlanCarryOver.Survey]) -> String {
        let entries = surveys.reduce(0) { $0 + $1.count }
        let children = surveys.count
        let start = DateFormatters.mediumDate.string(from: YearPlanStaleness.currentYearStart())
        return "\(entries) \(entries == 1 ? "entry" : "entries") for \(children) "
            + "\(children == 1 ? "child" : "children") target dates before \(start) — last year's "
            + "intentions, not lessons they have fallen behind on. Re-dating keeps each child's "
            + "order and the school days between her targets."
    }
}

#Preview {
    RolloverCarryOverSectionPreview()
}

private struct RolloverCarryOverSectionPreview: View {
    @State private var viewModel = SchoolYearRolloverViewModel()

    var body: some View {
        List {
            RolloverCarryOverSection(viewModel: viewModel, store: SchoolYearStore())
        }
    }
}
