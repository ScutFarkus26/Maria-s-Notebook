import SwiftUI
import SwiftData

extension TodoEditSheet {
    // MARK: - Student Section
    @ViewBuilder
    var studentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            studentSectionHeader

            if students.isEmpty {
                emptyStudentsView
            } else {
                selectedStudentsChips
                availableStudentsList
            }
        }
    }

    @ViewBuilder
    var studentSectionHeader: some View {
        HStack {
            Text("Assigned To")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            suggestButton
        }
    }

    @ViewBuilder
    var suggestButton: some View {
        Button {
            Task { await suggestStudents() }
        } label: {
            HStack(spacing: 4) {
                if isSuggestingStudents {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Suggest")
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
            }
            .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
        .disabled(isSuggestingStudents || students.isEmpty || title.isEmpty)
    }

    @ViewBuilder
    var emptyStudentsView: some View {
        Text("No students available")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    var selectedStudentsChips: some View {
        if !selectedStudents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedStudents) { student in
                        TodoStudentChip(student: student) {
                            _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedStudentIDs.remove(student.id.uuidString)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    var availableStudentsList: some View {
        let available = students.filter { !selectedStudentIDs.contains($0.id.uuidString) }
        if !available.isEmpty {
            VStack(spacing: 6) {
                ForEach(available) { student in
                    Button {
                        adaptiveWithAnimation(Animation.spring(response: 0.25, dampingFraction: 0.85)) {
                            _ = selectedStudentIDs.insert(student.id.uuidString)
                        }
                    } label: {
                        HStack {
                            Text(student.fullName)
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func suggestStudents() async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            isSuggestingStudents = true
            defer { isSuggestingStudents = false }

            let combinedText = "\(title) \(notes)"

            do {
                let extractedNames = try await TodoStudentSuggestionService.extractStudentNames(
                    from: combinedText,
                    availableStudents: students
                )

                let matchedStudents = TodoStudentSuggestionService.matchStudents(
                    extractedNames: extractedNames,
                    from: students
                )

                // Add matched students to selection
                for student in matchedStudents {
                    _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedStudentIDs.insert(student.id.uuidString)
                    }
                }
            } catch {
                // Silently fail - Apple Intelligence might not be available
            }
        }
        #endif
    }
}
