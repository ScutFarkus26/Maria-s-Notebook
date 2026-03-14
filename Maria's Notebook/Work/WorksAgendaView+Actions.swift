// WorksAgendaView+Actions.swift
// Calendar navigation and work item action methods for WorksAgendaView.

import SwiftUI
import SwiftData
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
            if !SchoolDayChecker.isNonSchoolDay(cursor, using: modelContext) { remaining -= 1 }
        }
        calendarStartDate = cursor
    }

    // MARK: - Actions

    func openDetail(_ w: WorkModel) {
        // Force save before opening
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }

        selected = nil
        let token = SelectionToken(id: UUID(), workID: w.id)
        Task { @MainActor in
            selected = token
        }
    }

    func markCompleted(_ w: WorkModel) {
        w.status = .complete
        _ = saveCoordinator.save(modelContext, reason: "Mark work completed")
        HapticService.shared.notification(.success)
    }

    func scheduleToday(_ w: WorkModel) {
        let today = AppCalendar.startOfDay(Date())
        // Phase 6: Update or create a WorkCheckIn for this work
        let workID: UUID = w.id
        let workIDString = workID.uuidString
        var fetch = FetchDescriptor<WorkCheckIn>(
            predicate: #Predicate<WorkCheckIn> { $0.workID == workIDString },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        fetch.fetchLimit = 1
        do {
            if let first = try modelContext.fetch(fetch).first {
                first.date = today
            } else {
                let item = WorkCheckIn(
                    id: UUID(), workID: workID,
                    date: today, status: .scheduled,
                    purpose: "progressCheck"
                )
                modelContext.insert(item)
            }
        } catch {
            Self.logger.warning("Failed to fetch WorkCheckIn: \(error)")
            // Create new check-in as fallback
            let item = WorkCheckIn(
                id: UUID(), workID: workID,
                date: today, status: .scheduled,
                purpose: "progressCheck"
            )
            modelContext.insert(item)
        }
        w.dueAt = today
        _ = saveCoordinator.save(modelContext, reason: "Quick schedule today")
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
