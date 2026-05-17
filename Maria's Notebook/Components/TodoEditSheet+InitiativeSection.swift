// TodoEditSheet+InitiativeSection.swift
// "Initiative" picker — link a todo to one Planning Initiative.

import SwiftUI
import CoreData

extension TodoEditSheet {
    @ViewBuilder
    var initiativeSection: some View {
        InitiativePickerSection(selectedInitiativeID: $selectedInitiativeID)
    }
}

/// Standalone view (not an extension closure) so it can host its own @FetchRequest.
struct InitiativePickerSection: View {
    @Binding var selectedInitiativeID: String?

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDInitiative.title, ascending: true)
        ],
        predicate: NSPredicate(format: "completedAt == nil")
    ) private var activeInitiatives: FetchedResults<CDInitiative>

    private var selectedInitiative: CDInitiative? {
        guard let idString = selectedInitiativeID,
              let uuid = UUID(uuidString: idString) else { return nil }
        return activeInitiatives.first { $0.id == uuid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Initiative")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 10) {
                Menu {
                    Button("None") { selectedInitiativeID = nil }
                    Divider()
                    ForEach(activeInitiatives, id: \.objectID) { initiative in
                        Button {
                            selectedInitiativeID = initiative.id?.uuidString
                        } label: {
                            Label {
                                Text(initiative.title.isEmpty ? "Untitled" : initiative.title)
                            } icon: {
                                Image(systemName: initiative.symbol ?? InitiativeSymbol.defaultValue.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if let initiative = selectedInitiative {
                            Image(systemName: initiative.symbol ?? InitiativeSymbol.defaultValue.rawValue)
                                .foregroundStyle(InitiativeColor.from(raw: initiative.colorRaw).swiftUIColor)
                            Text(initiative.title.isEmpty ? "Untitled" : initiative.title)
                        } else {
                            Image(systemName: "target")
                                .foregroundStyle(.secondary)
                            Text("No initiative")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 320)

                if selectedInitiativeID != nil {
                    Button {
                        selectedInitiativeID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Unlink from initiative")
                }
            }
        }
    }
}
