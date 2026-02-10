import SwiftUI

/// Helper for managing sheet presentations in StudentsView
struct StudentsViewSheetHelper {
    /// Standard sheet modifiers for student detail views
    static func studentDetailSheet<Content: View>(
        item: Binding<Student?>,
        @ViewBuilder content: @escaping (Student) -> Content
    ) -> some View {
        EmptyView()
            .sheet(item: item, onDismiss: {}) { student in
                content(student)
                    .id(student.id)
                #if os(macOS)
                    .frame(minWidth: 860, minHeight: 640)
                    .presentationSizingFitted()
                #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
    }

    /// Standard sheet modifiers for import preview views
    static func importPreviewSheet<Content: View>(
        item: Binding<StudentCSVImporter.Parsed?>,
        @ViewBuilder content: @escaping (StudentCSVImporter.Parsed) -> Content
    ) -> some View {
        EmptyView()
            .sheet(item: item, onDismiss: {}) { parsed in
                content(parsed)
                    .frame(minWidth: 620, minHeight: 520)
            }
    }
}
