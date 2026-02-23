// ScheduleCheckInSheet.swift
// Encapsulated schedule sheet UI used by WorksPlanningView

import SwiftUI
import SwiftData

struct ScheduleCheckInSheet: View {
    let workID: UUID
    let initialDate: Date
    let onCancel: () -> Void
    let onSave: (Date) -> Void

    @State private var date: Date

    init(workID: UUID, initialDate: Date, onCancel: @escaping () -> Void, onSave: @escaping (Date) -> Void) {
        self.workID = workID
        self.initialDate = initialDate
        self.onCancel = onCancel
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule Check-In").font(.headline)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(date) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 360)
        #endif
    }
}
