import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

struct WorksAgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @EnvironmentObject private var restoreCoordinator: RestoreCoordinator

    @Query(filter: #Predicate<WorkModel> { $0.statusRaw != "complete" }, sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var openWork: [WorkModel]
    
    // MEMORY OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    private var studentIDs: [UUID] {
        studentsForChangeDetection.map { $0.id }
    }
    
    // Lazy-loaded caches (only populated when needed)
    @State private var lessonsByIDCache: [UUID: Lesson] = [:]
    @State private var studentsByIDCache: [UUID: Student] = [:]

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var sortMode: WorkAgendaSortMode = .lesson
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var calendarHeightRatio: CGFloat = 0.5 // 50% calendar, 50% open work
    @State private var isCalendarMinimized: Bool = false

    @State private var selectedWorkID: UUID? = nil

    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let workID: UUID }
    @State private var selected: SelectionToken? = nil

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    private var lessonsByID: [UUID: Lesson] { lessonsByIDCache }
    private var studentsByID: [UUID: Student] { studentsByIDCache }

    /// Combined trigger for data reload - changes when any relevant data changes
    private var dataReloadTrigger: Int {
        var hasher = Hasher()
        hasher.combine(openWork.map { $0.id })
        hasher.combine(lessonIDs)
        hasher.combine(studentIDs)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
    }
    
    private func loadLessonsAndStudentsIfNeeded() {
        // Collect IDs from open work
        var neededLessonIDs = Set<UUID>()
        var neededStudentIDs = Set<UUID>()
        
        for work in openWork {
            if let lid = UUID(uuidString: work.lessonID) {
                neededLessonIDs.insert(lid)
            }
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
        }
        
        // Load only needed lessons
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededLessonIDs.isEmpty {
            let all = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
            let filtered = all.filter { neededLessonIDs.contains($0.id) }
            lessonsByIDCache = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            lessonsByIDCache = [:]
        }

        // Load only needed students
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let all = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
            let filtered = all.filter { neededStudentIDs.contains($0.id) }
            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let visible = TestStudentsFilter.filterVisible(filtered, show: showTestStudents, namesRaw: testStudentNamesRaw).uniqueByID
            studentsByIDCache = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            studentsByIDCache = [:]
        }
    }

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Top: Open Work grid
                        VStack(alignment: .leading, spacing: 8) {
                            header
                            Divider()
                            OpenWorkGrid(
                                works: openWorksFiltered(),
                                lessonsByID: lessonsByID,
                                studentsByID: studentsByID,
                                sortMode: sortMode,
                                onOpen: openDetail,
                                onMarkCompleted: markCompleted,
                                onScheduleToday: scheduleToday
                            )
                        }
                        .frame(height: geo.size.height * (isCalendarMinimized ? 1.0 : (1 - calendarHeightRatio)))

                        if !isCalendarMinimized {
                            Divider()

                            // Bottom: Calendar pane
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Planning Calendar").font(.title3.weight(.semibold))
                                    Spacer()
                                    Button("Today") { /* optional hook if needed */ }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                WorkAgendaCalendarPane(startDate: Date(), daysCount: 10)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: geo.size.height * calendarHeightRatio)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .navigationTitle("Work Agenda")
                .sheet(item: $selected, onDismiss: { selected = nil }) { token in
                    let id = token.workID
                    let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
                    if let w = modelContext.safeFetchFirst(fetch) {
                        WorkDetailView(workID: w.id)
                            .id(token.id)
                    } else {
                        ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .onAppear {
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: dataReloadTrigger) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Open Work") {
                HStack(spacing: 12) {
                    #if os(iOS)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCalendarMinimized.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    #endif
                    Picker("Sort", selection: $sortMode) {
                        ForEach(WorkAgendaSortMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    #if os(macOS)
                    Button {
                        printWorkView()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .help("Print open work")
                    Button {
                        exportWorkPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.down")
                    }
                    .help("Export open work to PDF")
                    #endif
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students or lessons", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        debouncedSearchText = searchText
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
    }

    // MARK: - Data helpers
    
    private func openWorksFiltered() -> [WorkModel] {
        // Filter open work in memory (anything NOT .complete)
        var works = openWork
        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(lessonTitle(forLessonID: w.lessonID))
                if let sid = UUID(uuidString: w.studentID), let s = studentsByID[sid] {
                    hay.append(s.firstName)
                    hay.append(s.lastName)
                    hay.append(s.fullName)
                    hay.append(StudentFormatter.displayName(for: s))
                }
                return hay.joined(separator: " ").lowercased().contains(query)
            }
        }
        return works
    }

    private func lessonTitle(forLessonID lessonID: String) -> String {
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(lessonID.prefix(6)))"
    }

    private func studentPrintName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private func statusLabel(for w: WorkModel) -> String {
        switch w.status {
        case .active:
            return "Practice"
        case .review:
            return "Follow-Up"
        case .complete:
            return "Completed"
        }
    }

    private func ageDays(for w: WorkModel) -> Int {
        let start = AppCalendar.startOfDay(w.createdAt)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private func latestNoteDate(for w: WorkModel) -> Date? {
        let notes = w.unifiedNotes ?? []
        return notes.map { max($0.updatedAt, $0.createdAt) }.max()
    }

    private func daysSince(_ date: Date) -> Int {
        let start = AppCalendar.startOfDay(date)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private func needsAttention(for w: WorkModel) -> Bool {
        // Needs attention if overdue by due date, or last note is 10+ days old.
        if let due = w.dueAt {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(due) < today { return true }
        }
        if let lastNoteDate = latestNoteDate(for: w) {
            return daysSince(lastNoteDate) >= 10
        }
        let schoolDaysSinceCreated = LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: w.createdAt,
            asOf: Date(),
            using: modelContext,
            calendar: calendar
        )
        return schoolDaysSinceCreated >= 10
    }

    private func makePrintItems(from works: [WorkModel]) -> [WorkPrintItem] {
        works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = (UUID(uuidString: w.studentID)).flatMap { studentsByID[$0] }.map(studentPrintName(for:)) ?? "Student"
            return WorkPrintItem(
                id: w.id,
                lessonTitle: title,
                studentName: student,
                statusLabel: statusLabel(for: w),
                ageDays: ageDays(for: w),
                dueAt: w.dueAt,
                needsAttention: needsAttention(for: w)
            )
        }
    }

    // MARK: - Actions
    private func openDetail(_ w: WorkModel) {
        // Force save before opening
        try? modelContext.save()
        
        selected = nil
        let token = SelectionToken(id: UUID(), workID: w.id)
        DispatchQueue.main.async { selected = token }
    }

    private func markCompleted(_ w: WorkModel) {
        w.status = .complete
        _ = saveCoordinator.save(modelContext, reason: "Mark work completed")
    }

    private func scheduleToday(_ w: WorkModel) {
        let today = AppCalendar.startOfDay(Date())
        // Update or create a single plan item for this work
        let workID: UUID = w.id
        let workIDString = workID.uuidString
        var fetch = FetchDescriptor<WorkPlanItem>(
            predicate: #Predicate<WorkPlanItem> { $0.workID == workIDString },
            sortBy: [SortDescriptor(\.scheduledDate, order: .forward)]
        )
        fetch.fetchLimit = 1
        if let first = (try? modelContext.fetch(fetch))?.first {
            first.scheduledDate = today
        } else {
            let item = WorkPlanItem(workID: w.id, scheduledDate: today, reason: .progressCheck, note: nil)
            modelContext.insert(item)
        }
        w.dueAt = today
        _ = saveCoordinator.save(modelContext, reason: "Quick schedule today")
    }

    #if os(macOS)
    private func printWorkView() {
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        guard let pdfData = renderWorksPDF(items: items, sortMode: sortMode, searchText: debouncedSearchText) else {
            NSSound.beep()
            return
        }

        let printInfo = configuredPrintInfo()
        if let doc = PDFDocument(data: pdfData),
           let operation = doc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false) {
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.run()
        }
    }

    private func exportWorkPDF() {
        // Capture current state BEFORE showing the panel (panel callback runs asynchronously)
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        let currentSortMode = sortMode
        let currentSearchText = debouncedSearchText

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Open Work.pdf"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let pdfData = self.renderWorksPDF(items: items, sortMode: currentSortMode, searchText: currentSearchText) else {
                NSSound.beep()
                return
            }
            do {
                try pdfData.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Renders the work items to PDF data using Core Graphics text drawing.
    /// Compact layout to minimize paper usage while maintaining readability.
    private func renderWorksPDF(items: [WorkPrintItem], sortMode: WorkAgendaSortMode, searchText: String) -> Data? {
        // Page setup - tighter margins for more content
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let contentWidth = pageWidth - (margin * 2)

        // Compact font setup
        let titleFont = NSFont.boldSystemFont(ofSize: 14)
        let headerFont = NSFont.boldSystemFont(ofSize: 10)
        let bodyFont = NSFont.systemFont(ofSize: 9)
        let smallFont = NSFont.systemFont(ofSize: 8)

        // Colors
        let blackColor = NSColor.black
        let grayColor = NSColor(white: 0.35, alpha: 1.0)
        let lightGrayColor = NSColor(white: 0.6, alpha: 1.0)

        // Group and sort items
        let sortedItems: [WorkPrintItem] = {
            switch sortMode {
            case .lesson:
                return items.sorted { $0.lessonTitle.localizedCaseInsensitiveCompare($1.lessonTitle) == .orderedAscending }
            case .student:
                return items.sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }
            case .age:
                return items.sorted { $0.ageDays > $1.ageDays }
            case .needsAttention:
                return items.sorted { lhs, rhs in
                    if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                    return lhs.ageDays > rhs.ageDays
                }
            }
        }()

        func groupKey(for item: WorkPrintItem) -> String {
            switch sortMode {
            case .lesson: return item.lessonTitle
            case .student: return item.studentName
            case .age:
                let days = item.ageDays
                if days <= 0 { return "Today" }
                else if days <= 3 { return "1-3 days" }
                else if days <= 7 { return "4-7 days" }
                else if days <= 14 { return "8-14 days" }
                else if days <= 30 { return "15-30 days" }
                else { return "30+ days" }
            case .needsAttention:
                return item.needsAttention ? "Needs Attention" : "Other"
            }
        }

        var groupOrder: [String] = []
        var groups: [String: [WorkPrintItem]] = [:]
        for item in sortedItems {
            let key = groupKey(for: item)
            if groups[key] == nil { groupOrder.append(key); groups[key] = [] }
            groups[key]?.append(item)
        }

        // Create PDF data
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        // Helper to draw text and return its height
        func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attrString)
            let fitWidth = maxWidth ?? contentWidth
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: attrString.length),
                nil, CGSize(width: fitWidth, height: CGFloat.greatestFiniteMagnitude), nil
            )

            let path = CGPath(rect: CGRect(x: point.x, y: point.y - suggestedSize.height, width: fitWidth, height: suggestedSize.height + 2), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrString.length), path, nil)
            CTFrameDraw(frame, context)

            return suggestedSize.height
        }

        // Helper to draw a single line of text (no wrapping) - more efficient for compact items
        func drawLine(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            context.textPosition = point
            CTLineDraw(line, context)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        // Start first page
        var currentPage = 1
        context.beginPDFPage(nil)
        var yPosition = pageHeight - margin

        // Compact header: Title and metadata on same area
        let titleText = "Open Work"
        yPosition -= drawText(titleText, at: CGPoint(x: margin, y: yPosition), font: titleFont, color: blackColor)

        // Metadata line - all on one line
        var metaText = "\(dateFormatter.string(from: Date())) • \(sortMode.rawValue) • \(items.count) items"
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            metaText += " • Filter: \(searchText)"
        }
        yPosition -= drawText(metaText, at: CGPoint(x: margin, y: yPosition), font: smallFont, color: grayColor)
        yPosition -= 8

        // Draw a separator line
        context.setStrokeColor(lightGrayColor.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: yPosition))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
        context.strokePath()
        yPosition -= 6

        // Draw groups
        for groupName in groupOrder {
            guard let groupItems = groups[groupName] else { continue }

            // Check if we need a new page
            if yPosition < margin + 30 {
                context.endPDFPage()
                context.beginPDFPage(nil)
                currentPage += 1
                yPosition = pageHeight - margin
            }

            // Compact group header with background
            let headerHeight: CGFloat = 12
            context.setFillColor(NSColor(white: 0.92, alpha: 1.0).cgColor)
            context.fill(CGRect(x: margin, y: yPosition - headerHeight, width: contentWidth, height: headerHeight))

            drawLine("\(groupName) (\(groupItems.count))", at: CGPoint(x: margin + 4, y: yPosition - headerHeight + 3), font: headerFont, color: blackColor)
            yPosition -= headerHeight + 2

            // Draw items in compact single-line format
            for item in groupItems {
                // Check if we need a new page
                if yPosition < margin + 14 {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    currentPage += 1
                    yPosition = pageHeight - margin
                }

                // Build compact single-line item: "□ Lesson — Student  |  Status • 5d • Due 2/14"
                var itemText = "☐ "

                // What to show depends on sort mode - avoid redundancy
                switch sortMode {
                case .lesson:
                    itemText += item.studentName
                case .student:
                    itemText += item.lessonTitle
                default:
                    itemText += "\(item.lessonTitle) — \(item.studentName)"
                }

                // Add compact details
                var details: [String] = []
                details.append(item.statusLabel)
                details.append("\(item.ageDays)d")
                if let due = item.dueAt {
                    details.append(dateFormatter.string(from: due))
                }
                if item.needsAttention {
                    details.append("⚠")
                }

                let detailsText = details.joined(separator: " • ")

                // Draw checkbox and name on left, details on right
                drawLine(itemText, at: CGPoint(x: margin + 6, y: yPosition - 9), font: bodyFont, color: blackColor)

                // Right-align details
                let detailsAttr: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: grayColor]
                let detailsSize = (detailsText as NSString).size(withAttributes: detailsAttr)
                drawLine(detailsText, at: CGPoint(x: pageWidth - margin - detailsSize.width, y: yPosition - 9), font: smallFont, color: grayColor)

                yPosition -= 12
            }

            yPosition -= 4 // Small space between groups
        }

        // Handle empty state
        if items.isEmpty {
            yPosition -= drawText("No open work items.", at: CGPoint(x: margin, y: yPosition), font: bodyFont, color: grayColor)
        }

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func configuredPrintInfo() -> NSPrintInfo {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        return printInfo
    }
    #endif
}

fileprivate struct WorkPrintItem: Identifiable {
    let id: UUID
    let lessonTitle: String
    let studentName: String
    let statusLabel: String
    let ageDays: Int
    let dueAt: Date?
    let needsAttention: Bool
}

private struct WorksAgendaPrintView: View {
    let title: String
    let generatedAt: Date
    let sortMode: WorkAgendaSortMode
    let searchText: String
    let items: [WorkPrintItem]

    // Avoid dynamic system colors in print/PDF output to prevent "white on white" rendering.
    private var secondaryTextColor: Color { Color(white: 0.35) }

    private var groupedItems: [(key: String, items: [WorkPrintItem])] {
        var order: [String] = []
        var buckets: [String: [WorkPrintItem]] = [:]
        for item in sortedItems {
            let key = groupKey(for: item)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(item)
        }
        return order.map { key in (key: key, items: buckets[key] ?? []) }
    }

    private var sortedItems: [WorkPrintItem] {
        switch sortMode {
        case .lesson:
            return items.sorted { $0.lessonTitle.localizedCaseInsensitiveCompare($1.lessonTitle) == .orderedAscending }
        case .student:
            return items.sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }
        case .age:
            return items.sorted { $0.ageDays > $1.ageDays }
        case .needsAttention:
            return items.sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                return lhs.ageDays > rhs.ageDays
            }
        }
    }

    private func groupKey(for item: WorkPrintItem) -> String {
        switch sortMode {
        case .lesson:
            return item.lessonTitle
        case .student:
            return item.studentName
        case .age:
            return ageBucketLabel(forDays: item.ageDays)
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }

    private func ageBucketLabel(forDays days: Int) -> String {
        if days <= 0 { return "Today" }
        else if days <= 3 { return "1-3 days" }
        else if days <= 7 { return "4-7 days" }
        else if days <= 14 { return "8-14 days" }
        else if days <= 30 { return "15-30 days" }
        else { return "30+ days" }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private func subtitle(for item: WorkPrintItem) -> String {
        var parts: [String] = [item.statusLabel, "\(item.ageDays)d"]
        if let due = item.dueAt {
            parts.append("Due \(formattedDate(due))")
        }
        if item.needsAttention {
            parts.append("Needs attention")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                Text("Generated \(formattedDate(generatedAt))")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryTextColor)
                Text("Sort: \(sortMode.rawValue)  |  Total: \(items.count)")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryTextColor)
                if !searchText.trimmed().isEmpty {
                    Text("Filter: \(searchText)")
                        .font(.system(size: 10))
                        .foregroundColor(secondaryTextColor)
                }
            }

            if items.isEmpty {
                Text("No open work to print.")
                    .font(.system(size: 11))
                    .foregroundColor(secondaryTextColor)
            } else {
                ForEach(groupedItems, id: \.key) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(section.key) (\(section.items.count))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().frame(height: 1).foregroundColor(secondaryTextColor), alignment: .bottom)
                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.lessonTitle) - \(item.studentName)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.black)
                                Text(subtitle(for: item))
                                    .font(.system(size: 9))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
        // Printing runs in its own context and can inherit dark mode.
        // Force light colors so text is visible on white paper/preview.
        .environment(\.colorScheme, .light)
        .background(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    // Encapsulate data setup in a closure to avoid Void return statements in ViewBuilder
    let container: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: configuration) else {
            fatalError("Failed to create preview container - this should never happen for in-memory containers")
        }
        let ctx = container.mainContext
        
        let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
        let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
        ctx.insert(s)
        ctx.insert(l)
        let w = WorkModel(status: .active, studentID: s.id.uuidString, lessonID: l.id.uuidString)
        ctx.insert(w)
        return container
    }()

    WorksAgendaView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}
