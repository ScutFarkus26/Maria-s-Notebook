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

    // MARK: - Calendar Navigation

    func moveCalendarStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = AppCalendar.startOfDay(calendarStartDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !SchoolDayChecker.isNonSchoolDay(cursor, using: viewContext) { remaining -= 1 }
        }
        calendarStartDate = cursor
    }

    // MARK: - Actions

    func openDetail(_ w: CDWorkModel) {
        // Force save before opening
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }

        selected = nil
        let token = SelectionToken(id: UUID(), workID: w.id ?? UUID())
        Task { @MainActor in
            selected = token
        }
    }

    func markCompleted(_ w: CDWorkModel) {
        w.status = .complete
        saveCoordinator.save(viewContext, reason: "Mark work completed")
        HapticService.shared.notification(.success)
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
        panel.nameFieldStringValue = "Open Work.pdf"
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
}
