// ObservationModeView+StudentPicker.swift

import SwiftUI

extension ObservationModeView {

    // MARK: - Student Picker Sheet

    var studentPickerSheet: some View {
        NavigationStack {
            List {
              ForEach(viewModel.allStudents) { student in
                Button {
                    if viewModel.selectedStudentIDs.contains(student.id) {
                        viewModel.selectedStudentIDs.remove(student.id)
                    } else {
                        viewModel.selectedStudentIDs.insert(student.id)
                    }
                } label: {
                    HStack {
                        Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text(student.level.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if viewModel.selectedStudentIDs.contains(student.id) {
                            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
              }
            }
            .navigationTitle("Select Students")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.showingStudentPicker = false
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
