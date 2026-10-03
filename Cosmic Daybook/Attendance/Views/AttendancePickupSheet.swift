import SwiftUI

/// Leaving Early…: when a child is due to be picked up, set ahead from the
/// attendance menu ("dentist at 1:30"). The time goes on the day's shared
/// record (`CDAttendanceRecord.leavesAt`), so the guide and every assistant
/// see "leaves 1:30", and the Daybook Assistant reminds before it. Setting it
/// marks nothing: Left Early is still marked when the child goes.
struct AttendancePickupSheet: View {
    let studentName: String
    /// The day on screen; the picked time is put on it.
    let day: Date
    /// The time already set, if any. With one, the sheet offers Remove.
    let current: Date?
    /// Where the picker starts (`AttendanceRules.suggestedPickup`).
    let suggested: Date
    /// One line under the picker saying who else sees it.
    let sharedWith: String
    /// The new time on `day`, or nil to remove it.
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Leaves at", selection: $time, displayedComponents: .hourAndMinute)
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        #endif
                } footer: {
                    Text(sharedWith)
                }
                if current != nil {
                    Section {
                        Button("Remove Pickup Time", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("\(studentName) Leaving Early")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(AttendanceRules.pickup(time, on: day))
                        dismiss()
                    }
                }
            }
        }
        .onAppear { time = suggested }
        #if os(iOS)
        .presentationDetents([.medium])
        #else
        .frame(minWidth: 320, minHeight: 200)
        #endif
    }
}
