import SwiftUI
import CoreData
import UserNotifications

struct InitiativeEditorSheet: View {
    let initiative: CDInitiative?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDInitiative.area, ascending: true)]
    ) private var allInitiatives: FetchedResults<CDInitiative>

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var hasDeadline: Bool = false
    @State private var deadline: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var area: String = ""
    @State private var color: InitiativeColor = .defaultValue
    @State private var symbol: InitiativeSymbol = .defaultValue

    init(initiative: CDInitiative?) {
        self.initiative = initiative
        _title = State(initialValue: initiative?.title ?? "")
        _notes = State(initialValue: initiative?.notes ?? "")
        if let d = initiative?.deadline {
            _hasDeadline = State(initialValue: true)
            _deadline = State(initialValue: d)
        }
        _area = State(initialValue: initiative?.area ?? "")
        _color = State(initialValue: InitiativeColor.from(raw: initiative?.colorRaw))
        if let raw = initiative?.symbol, let s = InitiativeSymbol(rawValue: raw) {
            _symbol = State(initialValue: s)
        }
    }

    private var existingAreas: [String] {
        let fromData = Set(allInitiatives.compactMap { $0.area?.trimmed() }.filter { !$0.isEmpty })
        return Array(Set(fromData).union(InitiativeAreaSuggestion.common)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(initiative == nil ? "New Initiative" : "Edit Initiative")
                .font(.title2).fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 80, maxHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            Toggle("Deadline", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("Due", selection: $deadline, displayedComponents: [.date])
                    .datePickerStyle(.compact)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Area").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. Reports, Trips", text: $area)
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(existingAreas, id: \.self) { suggestion in
                                Button(suggestion) { area = suggestion }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color").font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $color) {
                        ForEach(InitiativeColor.allCases) { c in
                            Label {
                                Text(c.rawValue.capitalized)
                            } icon: {
                                Circle().fill(c.swiftUIColor).frame(width: 12, height: 12)
                            }
                            .tag(c)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Symbol").font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $symbol) {
                        ForEach(InitiativeSymbol.allCases) { s in
                            Image(systemName: s.rawValue).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(minWidth: 520)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var isValid: Bool { !title.trimmed().isEmpty }

    private func save() {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }
        let trimmedArea = area.trimmed()

        let target: CDInitiative
        if let initiative {
            target = initiative
        } else {
            target = CDInitiative(context: modelContext)
        }
        target.title = trimmedTitle
        target.notes = notes
        target.deadline = hasDeadline ? deadline : nil
        target.area = trimmedArea.isEmpty ? nil : trimmedArea
        target.colorRaw = color.rawValue
        target.symbol = symbol.rawValue
        target.modifiedAt = Date()

        _ = saveCoordinator.save(modelContext, reason: initiative == nil ? "New Initiative" : "Edit Initiative")

        // Reschedule notifications whenever the deadline (or anything that affects messaging) changes.
        Task { @MainActor in
            do {
                if target.deadline == nil || target.isCompleted {
                    TodoNotificationService.shared.cancelNotifications(for: target, context: modelContext)
                } else {
                    if await TodoNotificationService.shared.checkAuthorizationStatus() == .notDetermined {
                        _ = await TodoNotificationService.shared.requestAuthorization()
                    }
                    try await TodoNotificationService.shared.rescheduleNotifications(for: target, context: modelContext)
                }
            } catch {
                // Non-fatal: the initiative still saved.
            }
        }

        dismiss()
    }
}
