import SwiftUI
import CoreData

/// A compact sheet for picking a meeting date.
struct MeetingDatePickerSheet: View {
    let studentName: String
    let onSchedule: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Meeting Date",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Button {
                    onSchedule(selectedDate)
                    dismiss()
                } label: {
                    Text("Schedule")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Meeting with \(studentName)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}

#Preview {
    MeetingDatePickerSheet(studentName: "Alan T.") { date in
        print("Scheduled for \(date)")
    }
}
