import SwiftUI

struct StudentCSVMappingView: View {
    let headers: [String]
    @State private var mapping: StudentCSVImporter.Mapping
    let onCancel: () -> Void
    let onConfirm: (StudentCSVImporter.Mapping) -> Void

    init(headers: [String], onCancel: @escaping () -> Void, onConfirm: @escaping (StudentCSVImporter.Mapping) -> Void) {
        self.headers = headers
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _mapping = State(initialValue: StudentCSVImporter.detectMapping(headers: headers))
    }

    private var canContinue: Bool {
        (mapping.firstName != nil && mapping.lastName != nil) || (mapping.fullName != nil)
    }

    private func selectionBinding(for keyPath: WritableKeyPath<StudentCSVImporter.Mapping, Int?>) -> Binding<Int> {
        Binding<Int>(
            get: { mapping[keyPath: keyPath] ?? -1 },
            set: { newValue in
                mapping[keyPath: keyPath] = (newValue >= 0 ? newValue : nil)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Map Columns")
                    .font(AppTheme.ScaledFont.titleMedium)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Divider()
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                Text("Choose which CSV columns map to student fields. You must provide either First + Last, or a Full Name column.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)

                Form {
                    Picker("First Name", selection: selectionBinding(for: \.firstName)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }
                    Picker("Last Name", selection: selectionBinding(for: \.lastName)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }
                    Picker("Full Name", selection: selectionBinding(for: \.fullName)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }
                    Picker("Birthday", selection: selectionBinding(for: \.birthday)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }
                    Picker("Start Date", selection: selectionBinding(for: \.startDate)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }
                    Picker("Level", selection: selectionBinding(for: \.level)) {
                        Text("None").tag(-1)
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i]).tag(i)
                        }
                    }

                    Picker("Split Full Name On", selection: Binding<String>(
                        get: { mapping.splitFullNameOn },
                        set: { mapping.splitFullNameOn = $0 }
                    )) {
                        Text("Space").tag(" ")
                        Text("Comma").tag(",")
                    }
                    .pickerStyle(.segmented)
                }
                .formStyle(.grouped)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Continue") { onConfirm(mapping) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
