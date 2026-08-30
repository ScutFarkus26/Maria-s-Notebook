// WorksAgendaView+Actions.swift
// Calendar navigation and work item action methods for WorksAgendaView.

import SwiftUI
import CoreData
import OSLog
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

extension WorksAgendaView {

    // MARK: - Actions

    func openDetail(_ w: CDWorkModel) {
        // Force save before opening
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }

        guard let workID = w.id else { return }

        #if os(macOS)
        openWindow(id: "WorkDetailWindow", value: workID)
        #else
        selected = nil
        let token = SelectionToken(id: UUID(), workID: workID)
        Task { @MainActor in
            selected = token
        }
        #endif
    }

    func markCompleted(_ w: CDWorkModel) {
        guard let workID = w.id else { return }
        // Route through the canonical completion path so completedAt is set
        // and the readiness auto-unlock check runs (handles save + haptic).
        WorkRepository(context: viewContext).markWorkCompleted(id: workID)
    }

    func scheduleToday(_ w: CDWorkModel) {
        let today = AppCalendar.startOfDay(Date())
        let workIDString = w.id?.uuidString ?? ""
        let request: NSFetchRequest<CDWorkCheckIn> = NSFetchRequest(entityName: "WorkCheckIn")
        request.predicate = NSPredicate(format: "workID == %@", workIDString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: true)]
        request.fetchLimit = 1
        do {
            if let first = try viewContext.fetch(request).first {
                first.date = today
            } else {
                let item = CDWorkCheckIn(context: viewContext)
                item.workID = workIDString
                item.date = today
                item.status = .scheduled
                item.purpose = "progressCheck"
            }
        } catch {
            Self.logger.warning("Failed to fetch CDWorkCheckIn: \(error)")
            let item = CDWorkCheckIn(context: viewContext)
            item.workID = workIDString
            item.date = today
            item.status = .scheduled
            item.purpose = "progressCheck"
        }
        w.dueAt = today
        saveCoordinator.save(viewContext, reason: "Quick schedule today")
    }

    #if os(macOS)
    func printWorkView() {
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        guard let pdfData = WorkPDFRenderer.renderPDF(
            items: items, sortMode: sortMode,
            searchText: debouncedSearchText
        ) else {
            NSSound.beep()
            return
        }

        let printInfo = WorkPDFRenderer.configuredPrintInfo()
        if let doc = PDFDocument(data: pdfData),
           let operation = doc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false) {
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.run()
        }
    }

    func exportWorkPDF() {
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        let currentSortMode = sortMode
        let currentSearchText = debouncedSearchText

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Children Working.pdf"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let pdfData = WorkPDFRenderer.renderPDF(
                items: items,
                sortMode: currentSortMode,
                searchText: currentSearchText
            ) else {
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
    #endif

    // MARK: - Opening Records

    /// A caller asking for a particular record only has to get it into the
    /// workspace — the partition already knows which list holds it, so the
    /// requested scope is a fallback, not an instruction.
    func consumeWorkspaceRequestIfNeeded() {
        guard let request = appRouter.consumeLessonsAndWorkRequest() else { return }
        focusedPresentationID = request.presentationID
        focusedWorkID = request.workID

        let destination = bucketHolding(request) ?? request.scope
        guard destination != .scheduled else {
            // Already on screen in the pinned pane — open it and let the
            // calendar reveal the record, rather than switching the list above.
            isCalendarExpanded = true
            return
        }
        workspaceScopeRaw = destination.rawValue
    }

    func bucketHolding(_ request: AppRouter.LessonsAndWorkRequest) -> TriageBucket? {
        if let workID = request.workID {
            return TriageBucket.workspaceCases.first { bucket in
                partition.work[bucket].contains { $0.id == workID }
            }
        }
        if let presentationID = request.presentationID {
            return TriageBucket.workspaceCases.first { bucket in
                partition.presentations[bucket].contains { $0.id == presentationID }
            }
        }
        return nil
    }

    func openPresentation(_ assignment: CDLessonAssignment) {
        #if os(macOS)
        guard let id = assignment.id else { return }
        openWindow(id: "PresentationDetailWindow", value: id)
        #else
        selectedLessonAssignment = assignment
        #endif
    }

    func openWork(id: UUID) {
        guard let work = fetchWork(id: id) else { return }
        openDetail(work)
    }

    @ViewBuilder
    func sheetContent(for token: SelectionToken) -> some View {
        let work = fetchWork(id: token.workID)
        if let w = work {
            WorkDetailView(workID: w.id ?? UUID())
                .id(token.id)
        } else {
            ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
        }
    }

    func fetchWork(id: UUID) -> CDWorkModel? {
        let request: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return viewContext.safeFetch(request).first
    }
}
