import SwiftUI
import SwiftData
import OSLog

private struct EntryRow: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var subject: String = ""
    var group: String = ""
    var subheading: String = ""
    var writeUp: String = ""
}

// swiftlint:disable:next type_body_length
public struct BulkLessonsEntryView: View {
    private static let logger = Logger.lessons

    let defaultSubject: String?
    let defaultGroup: String?
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var repository: LessonRepository {
        LessonRepository(context: modelContext, saveCoordinator: nil)
    }

    @State private var rows: [EntryRow] = []
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var quickSubject: String = ""
    @State private var quickGroup: String = ""
    @State private var batchSource: LessonSource = .album
    @State private var batchPersonalKind: PersonalLessonKind = .personal

    public init(
        defaultSubject: String? = nil,
        defaultGroup: String? = nil,
        onDone: (() -> Void)? = nil
    ) {
        self.defaultSubject = defaultSubject?.trimmed()
        self.defaultGroup = defaultGroup?.trimmed()
        self.onDone = onDone
        _rows = State(initialValue: Self.initialRows(
            count: 10, defaultSubject: self.defaultSubject,
            defaultGroup: self.defaultGroup
        ))
    }

    private let columnSpacing: CGFloat = 8
    private let selectionColumnWidth: CGFloat = 28
    private let weights: [CGFloat] = [2, 1, 1, 2, 3] // Name, Subject, Group, Subheading, WriteUp

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let count = weights.count
        let totalSpacing = columnSpacing * CGFloat(count) // spacing between selection and each of the 5 columns
        let available = max(0, total - selectionColumnWidth - totalSpacing)
        let sum = weights.reduce(0, +)
        return weights.map { available * ($0 / sum) }
    }

    private enum FillColumn { case subject, group }

    private func applyFill(_ column: FillColumn, value: String, toSelected: Bool) {
        let trimmed = value.trimmed()
        guard !trimmed.isEmpty else { return }
        for i in rows.indices {
            let id = rows[i].id
            if toSelected && !selectedRowIDs.contains(id) { continue }
            switch column {
            case .subject: rows[i].subject = trimmed
            case .group: rows[i].group = trimmed
            }
        }
    }

    private func toggleSelectAll(_ select: Bool) {
        if select {
            selectedRowIDs = Set(rows.map(\.id))
        } else {
            selectedRowIDs.removeAll()
        }
    }

    private static func initialRows(count: Int, defaultSubject: String?, defaultGroup: String?) -> [EntryRow] {
        (0..<count).map { _ in
            var r = EntryRow()
            if let s = defaultSubject, !s.isEmpty { r.subject = s }
            if let g = defaultGroup, !g.isEmpty { r.group = g }
            return r
        }
    }

    private var validCount: Int {
        rows.filter { !$0.name.trimmed().isEmpty }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Bulk Add Lessons")
                    .font(AppTheme.ScaledFont.titleMedium)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()
                .padding(.top, 8)

            // Content
            VStack(alignment: .leading, spacing: 12) {
                Text("Type directly into the grid below. Each non-empty Name creates a lesson.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Source:")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Picker("Source", selection: $batchSource) {
                        ForEach(LessonSource.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    if batchSource == .personal {
                        Picker("Personal Type", selection: $batchPersonalKind) {
                            ForEach(PersonalLessonKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Spacer()
                }

                // Quick Fill bar
                HStack(spacing: 8) {
                    Label("Quick Fill", systemImage: "paintbrush")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.ScaledFont.captionSemibold)
                    Divider().frame(height: 16)
                    TextField("Subject", text: $quickSubject)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Button("Selected") { applyFill(.subject, value: quickSubject, toSelected: true) }
                        .buttonStyle(.bordered)
                    Button("All") { applyFill(.subject, value: quickSubject, toSelected: false) }
                        .buttonStyle(.bordered)
                    Divider().frame(height: 16)
                    TextField("Group", text: $quickGroup)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Button("Selected") { applyFill(.group, value: quickGroup, toSelected: true) }
                        .buttonStyle(.bordered)
                    Button("All") { applyFill(.group, value: quickGroup, toSelected: false) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(selectedRowIDs.count == rows.count && !rows.isEmpty ? "Deselect All" : "Select All") {
                        toggleSelectAll(!(selectedRowIDs.count == rows.count && !rows.isEmpty))
                    }
                    .buttonStyle(.bordered)
                }

                GeometryReader { geo in
                    let widths = columnWidths(total: geo.size.width - 16) // subtract small padding margin
                    VStack(alignment: .leading, spacing: 8) {
                        headerRow(widths: widths)
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach($rows) { $row in
                                    editorRow(for: $row, widths: widths)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(minHeight: 300)

                HStack(spacing: 12) {
                    Button {
                        addRows(5)
                    } label: {
                        Label("Add 5 Rows", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Footer
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button {
                        commit()
                    } label: {
                        Label("Add \(validCount) Lesson\(validCount == 1 ? "" : "s")", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validCount == 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func headerRow(widths: [CGFloat]) -> some View {
        HStack(spacing: columnSpacing) {
            // Selection header (empty space)
            Spacer().frame(width: selectionColumnWidth)
            Text("Name")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[0], alignment: .leading)
            Text("Subject")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[1], alignment: .leading)
            Text("Group")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[2], alignment: .leading)
            Text("Subheading")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[3], alignment: .leading)
            Text("Write Up")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[4], alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func editorRow(for row: Binding<EntryRow>, widths: [CGFloat]) -> some View {
        HStack(spacing: columnSpacing) {
            Button {
                let id = row.wrappedValue.id
                if selectedRowIDs.contains(id) { selectedRowIDs.remove(id) } else { selectedRowIDs.insert(id) }
            } label: {
                Image(systemName: selectedRowIDs.contains(row.wrappedValue.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedRowIDs.contains(row.wrappedValue.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: selectionColumnWidth)

            TextField("Lesson Name", text: row.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[0], alignment: .leading)
            TextField("Subject", text: row.subject)
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[1], alignment: .leading)
            TextField("Group", text: row.group)
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[2], alignment: .leading)
            TextField("Subheading", text: row.subheading)
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[3], alignment: .leading)
            TextField("Write Up", text: row.writeUp)
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[4], alignment: .leading)
        }
    }

    // MARK: - Actions
    private func addRows(_ count: Int) {
        let newRows = Self.initialRows(count: count, defaultSubject: defaultSubject, defaultGroup: defaultGroup)
        rows.append(contentsOf: newRows)
    }

    private func clearAll() {
        rows = Self.initialRows(count: 10, defaultSubject: defaultSubject, defaultGroup: defaultGroup)
        selectedRowIDs.removeAll()
    }

    // swiftlint:disable:next function_body_length
    private func commit() {
        let items = rows.map { r -> EntryRow in
            var copy = r
            copy.name = r.name.trimmed()
            copy.subject = r.subject.trimmed()
            copy.group = r.group.trimmed()
            copy.subheading = r.subheading.trimmed()
            copy.writeUp = r.writeUp.trimmed()
            return copy
        }.filter { !$0.name.isEmpty }

        guard !items.isEmpty else { return }

        // Build a map of max orderInGroup for each subject+group combination from existing lessons
        let allLessons = repository.fetchLessons()
        var maxOrderByGroup: [String: Int] = [:]
        for lesson in allLessons {
            let key = "\(lesson.subject)|\(lesson.group)"
            let current = maxOrderByGroup[key] ?? -1
            if lesson.orderInGroup > current {
                maxOrderByGroup[key] = lesson.orderInGroup
            }
        }

        var insertedLessons: [Lesson] = []
        for r in items {
            // Calculate the next orderInGroup for this subject+group
            let key = "\(r.subject)|\(r.group)"
            let nextOrder = (maxOrderByGroup[key] ?? -1) + 1
            maxOrderByGroup[key] = nextOrder

            let lesson = repository.createLesson(
                name: r.name,
                subject: r.subject,
                group: r.group,
                subheading: r.subheading,
                writeUp: r.writeUp,
                orderInGroup: nextOrder,
                source: batchSource,
                personalKind: batchSource == .personal ? batchPersonalKind : nil
            )
            insertedLessons.append(lesson)
        }
        do {
            try modelContext.save()

            // Automatically create/update Track objects for new subject/group combinations
            var processedGroups: Set<String> = []
            for lesson in insertedLessons {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                guard !subject.isEmpty && !group.isEmpty else { continue }

                let key = "\(subject)|\(group)"
                guard !processedGroups.contains(key) else { continue }
                processedGroups.insert(key)

                if GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                    do {
                        _ = try GroupTrackService.getOrCreateTrack(
                            subject: subject,
                            group: group,
                            modelContext: modelContext
                        )
                    } catch {
                        Self.logger.warning("Failed to create/update Track for \(subject)/\(group): \(error)")
                    }
                }
            }

            // Save track updates
            try modelContext.save()
        } catch {
            // Swallow save error for now; could surface an alert if needed
        }

        onDone?()
        dismiss()
    }
}

#Preview {
    BulkLessonsEntryView(defaultSubject: "Math", defaultGroup: "Decimal System")
}
