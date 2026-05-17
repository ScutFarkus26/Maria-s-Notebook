import SwiftUI
import OSLog
import CoreData

private struct EntryRow: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var area: String = ""
    var sequence: String = ""
    var section: String = ""
    var writeUp: String = ""
}

// swiftlint:disable:next type_body_length
public struct BulkLessonsEntryView: View {
    private static let logger = Logger.lessons

    let defaultArea: String?
    let defaultSequence: String?
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext

    private var repository: LessonRepository {
        LessonRepository(context: managedObjectContext, saveCoordinator: nil)
    }

    @State private var rows: [EntryRow] = []
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var quickArea: String = ""
    @State private var quickSequence: String = ""
    @State private var batchSource: LessonSource = .album
    @State private var batchPersonalKind: PersonalLessonKind = .personal

    public init(
        defaultArea: String? = nil,
        defaultSequence: String? = nil,
        onDone: (() -> Void)? = nil
    ) {
        self.defaultArea = defaultArea?.trimmed()
        self.defaultSequence = defaultSequence?.trimmed()
        self.onDone = onDone
        _rows = State(initialValue: Self.initialRows(
            count: 10, defaultArea: self.defaultArea,
            defaultSequence: self.defaultSequence
        ))
    }

    private let columnSpacing: CGFloat = 8
    private let selectionColumnWidth: CGFloat = 28
    private let weights: [CGFloat] = [2, 1, 1, 2, 3] // Name, Area, Group, Section, WriteUp

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let count = weights.count
        let totalSpacing = columnSpacing * CGFloat(count) // spacing between selection and each of the 5 columns
        let available = max(0, total - selectionColumnWidth - totalSpacing)
        let sum = weights.reduce(0, +)
        return weights.map { available * ($0 / sum) }
    }

    private enum FillColumn { case area, sequence }

    private func applyFill(_ column: FillColumn, value: String, toSelected: Bool) {
        let trimmed = value.trimmed()
        guard !trimmed.isEmpty else { return }
        for i in rows.indices {
            let id = rows[i].id
            if toSelected && !selectedRowIDs.contains(id) { continue }
            switch column {
            case .area: rows[i].area = trimmed
            case .sequence: rows[i].sequence = trimmed
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

    private static func initialRows(count: Int, defaultArea: String?, defaultSequence: String?) -> [EntryRow] {
        (0..<count).map { _ in
            var r = EntryRow()
            if let s = defaultArea, !s.isEmpty { r.area = s }
            if let g = defaultSequence, !g.isEmpty { r.sequence = g }
            return r
        }
    }

    private var validCount: Int {
        rows.filter { !$0.name.trimmed().isEmpty }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            bulkEntryHeader
            Divider().padding(.top, 8)
            bulkEntryContent
            bulkEntryFooter
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    // MARK: - Extracted Body Sections

    private var bulkEntryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Bulk Add Lessons")
                .font(AppTheme.ScaledFont.titleMedium)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var bulkEntryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type directly into the grid below. Each non-empty Name creates a lesson.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            sourcePickerRow
            quickFillBar

            GeometryReader { geo in
                let widths: [CGFloat] = columnWidths(total: geo.size.width - 16)
                VStack(alignment: .leading, spacing: 8) {
                    headerRow(widths: widths)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(rows) { row in
                                editorRow(rowID: row.id, widths: widths)
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
                Button { addRows(5) } label: { Label("Add 5 Rows", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Button(role: .destructive) { clearAll() } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var sourcePickerRow: some View {
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
    }

    private var quickFillBar: some View {
        HStack(spacing: 8) {
            Label("Quick Fill", systemImage: "paintbrush")
                .foregroundStyle(.secondary)
                .font(AppTheme.ScaledFont.captionSemibold)
            Divider().frame(height: 16)
            TextField("Area", text: $quickArea)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Selected") { applyFill(.area, value: quickArea, toSelected: true) }
                .buttonStyle(.bordered)
            Button("All") { applyFill(.area, value: quickArea, toSelected: false) }
                .buttonStyle(.bordered)
            Divider().frame(height: 16)
            TextField("Sequence", text: $quickSequence)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Button("Selected") { applyFill(.sequence, value: quickSequence, toSelected: true) }
                .buttonStyle(.bordered)
            Button("All") { applyFill(.sequence, value: quickSequence, toSelected: false) }
                .buttonStyle(.bordered)
            Spacer()
            Button(selectedRowIDs.count == rows.count && !rows.isEmpty ? "Deselect All" : "Select All") {
                toggleSelectAll(!(selectedRowIDs.count == rows.count && !rows.isEmpty))
            }
            .buttonStyle(.bordered)
        }
    }

    private var bulkEntryFooter: some View {
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

    private func headerRow(widths: [CGFloat]) -> some View {
        HStack(spacing: columnSpacing) {
            // Selection header (empty space)
            Spacer().frame(width: selectionColumnWidth)
            Text("Name")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[0], alignment: .leading)
            Text("Area")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[1], alignment: .leading)
            Text("Sequence")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: widths[2], alignment: .leading)
            Text("Section")
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
        .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func editorRow(rowID: UUID, widths: [CGFloat]) -> some View {
        HStack(spacing: columnSpacing) {
            Button {
                if selectedRowIDs.contains(rowID) { selectedRowIDs.remove(rowID) }
                else { selectedRowIDs.insert(rowID) }
            } label: {
                Image(systemName: selectedRowIDs.contains(rowID) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedRowIDs.contains(rowID) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: selectionColumnWidth)

            TextField("Lesson Name",
                      text: $rows.element(id: rowID, default: "", \.name))
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[0], alignment: .leading)
            TextField("Area",
                      text: $rows.element(id: rowID, default: "", \.area))
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[1], alignment: .leading)
            TextField("Sequence",
                      text: $rows.element(id: rowID, default: "", \.sequence))
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[2], alignment: .leading)
            TextField("Section",
                      text: $rows.element(id: rowID, default: "", \.section))
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[3], alignment: .leading)
            TextField("Write Up",
                      text: $rows.element(id: rowID, default: "", \.writeUp))
                .textFieldStyle(.roundedBorder)
                .frame(width: widths[4], alignment: .leading)
        }
    }

    // MARK: - Actions
    private func addRows(_ count: Int) {
        let newRows = Self.initialRows(count: count, defaultArea: defaultArea, defaultSequence: defaultSequence)
        rows.append(contentsOf: newRows)
    }

    private func clearAll() {
        rows = Self.initialRows(count: 10, defaultArea: defaultArea, defaultSequence: defaultSequence)
        selectedRowIDs.removeAll()
    }

    // swiftlint:disable:next function_body_length
    private func commit() {
        let items = rows.map { r -> EntryRow in
            var copy = r
            copy.name = r.name.trimmed()
            copy.area = r.area.trimmed()
            copy.sequence = r.sequence.trimmed()
            copy.section = r.section.trimmed()
            copy.writeUp = r.writeUp.trimmed()
            return copy
        }.filter { !$0.name.isEmpty }

        guard !items.isEmpty else { return }

        // Build a map of max orderInSequence for each area+sequence combination from existing lessons
        let allLessons = repository.fetchLessons()
        var maxOrderBySequence: [String: Int] = [:]
        for lesson in allLessons {
            let key = "\(lesson.area)|\(lesson.sequence)"
            let current = maxOrderBySequence[key] ?? -1
            let order = Int(lesson.orderInSequence)
            if order > current {
                maxOrderBySequence[key] = order
            }
        }

        var insertedLessons: [CDLesson] = []
        for r in items {
            // Calculate the next orderInSequence for this area+sequence
            let key = "\(r.area)|\(r.sequence)"
            let nextOrder = (maxOrderBySequence[key] ?? -1) + 1
            maxOrderBySequence[key] = nextOrder

            let lesson = repository.createLesson(
                name: r.name,
                area: r.area,
                sequence: r.sequence,
                section: r.section,
                writeUp: r.writeUp,
                orderInSequence: nextOrder,
                source: batchSource,
                personalKind: batchSource == .personal ? batchPersonalKind : nil
            )
            insertedLessons.append(lesson)
        }
        do {
            try managedObjectContext.save()

            // Automatically create/update CDTrackEntity objects for new area/sequence combinations
            var processedSequences: Set<String> = []
            for lesson in insertedLessons {
                let area = lesson.area.trimmed()
                let sequence = lesson.sequence.trimmed()
                guard !area.isEmpty && !sequence.isEmpty else { continue }

                let key = "\(area)|\(sequence)"
                guard !processedSequences.contains(key) else { continue }
                processedSequences.insert(key)

                if SequenceTrackService.isTrack(area: area, sequence: sequence, context: viewContext) {
                    do {
                        _ = try SequenceTrackService.getOrCreateTrack(
                            area: area,
                            sequence: sequence,
                            context: viewContext
                        )
                    } catch {
                        Self.logger.warning("Failed to create/update CDTrackEntity for \(area)/\(sequence): \(error)")
                    }
                }
            }

            // Save track updates
            try viewContext.save()
        } catch {
            // Swallow save error for now; could surface an alert if needed
        }

        onDone?()
        dismiss()
    }
}

#Preview {
    BulkLessonsEntryView(defaultArea: "Math", defaultSequence: "Decimal System")
}
