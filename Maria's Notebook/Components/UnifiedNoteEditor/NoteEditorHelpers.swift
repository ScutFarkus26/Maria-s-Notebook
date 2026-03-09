// NoteEditorHelpers.swift
// Helper methods for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - UnifiedNoteEditor Helpers Extension

extension UnifiedNoteEditor {

    // MARK: - Computed Properties

    var contextTitle: String {
        switch context {
        case .general: return "Quick Note"
        case .lesson: return "Lesson Note"
        case .work: return "Work Note"
        case .presentation: return "Presentation Note"
        case .attendance: return "Attendance Note"
        case .workCheckIn: return "Check-In Note"
        case .workCompletion: return "Completion Note"
        case .studentMeeting: return "Meeting Note"
        case .projectSession: return "Session Note"
        case .communityTopic: return "Topic Note"
        case .reminder: return "Reminder Note"
        case .schoolDayOverride: return "Override Note"
        }
    }

    var shouldShowStudentSelection: Bool {
        switch context {
        case .attendance, .workCompletion, .studentMeeting:
            return false
        case .presentation(let pres):
            // Planned presentations: notes are for the presentation, not specific students
            return pres.isPresented
        default:
            return true
        }
    }

    // shouldShowCategory removed — tags are always shown

    var preSelectedStudents: Set<UUID> {
        switch context {
        case .attendance(let record):
            if let studentID = UUID(uuidString: record.studentID) {
                return [studentID]
            }
        case .workCompletion(let record):
            if let studentID = UUID(uuidString: record.studentID) {
                return [studentID]
            }
        case .studentMeeting(let meeting):
            if let studentID = UUID(uuidString: meeting.studentID) {
                return [studentID]
            }
        case .presentation(let pres):
            // Only pre-select students for already-presented lessons
            return pres.isPresented ? Set(pres.studentUUIDs) : []
        case .work(let work):
            return Set((work.participants ?? []).compactMap { UUID(uuidString: $0.studentID) })
        default:
            break
        }
        return []
    }

    var canSave: Bool {
        if !shouldShowStudentSelection {
            return !bodyText.trimmed().isEmpty
        }
        return !selectedStudentIDs.isEmpty && !bodyText.trimmed().isEmpty
    }

    nonisolated var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    nonisolated var notesBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(UIConstants.OpacityConstants.statusBg)
        #else
        return Color(uiColor: .secondarySystemBackground).opacity(UIConstants.OpacityConstants.statusBg)
        #endif
    }

    // MARK: - Setup

    func setupInitialState() {
        selectedStudentIDs = preSelectedStudents

        if let note = initialNote {
            bodyText = note.body
            tags = note.tags
            includeInReport = note.includeInReport
            needsFollowUp = note.needsFollowUp
            imagePath = note.imagePath
            // Store original image path for cleanup if image changes
            originalImagePath = note.imagePath

            switch note.scope {
            case .student(let id):
                selectedStudentIDs = [id]
            case .students(let ids):
                selectedStudentIDs = Set(ids)
            case .all:
                break
            }
        } else {
            if case .attendance = context {
                tags = [TagHelper.tagFromNoteCategory("attendance")]
            }
        }
    }

    // MARK: - Name Display

    func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    // MARK: - Photo Handling

    /// Deletes the previous image if it differs from the original (to prevent orphaned files)
    private func cleanupPreviousImageIfNeeded(newPath: String?) {
        // If we have an existing imagePath that's different from both:
        // 1. The new path we're setting
        // 2. The original path (which belongs to the existing note)
        // Then we need to delete it to prevent orphaned files
        if let existingPath = imagePath,
           !existingPath.isEmpty,
           existingPath != newPath,
           existingPath != originalImagePath {
            do {
                try PhotoStorageService.deleteImage(filename: existingPath)
            } catch {
                print("⚠️ [\(#function)] Failed to delete previous image: \(error)")
            }
        }
    }

    func handlePhotoChange(_ newItem: PhotosPickerItem?) {
        Task {
            if let newItem = newItem {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        #if os(macOS)
                        if let image = NSImage(data: data) {
                        selectedImage = image
                        do {
                            let newPath = try PhotoStorageService.saveImage(image)
                            // Clean up any intermediate image that might have been selected
                            cleanupPreviousImageIfNeeded(newPath: newPath)
                            imagePath = newPath
                        } catch {
                            #if DEBUG
                            print("Error saving image: \(error)")
                            #endif
                            selectedImage = nil
                            selectedPhoto = nil
                        }
                    }
                    #else
                    if let image = UIImage(data: data) {
                        handleCameraImage(image)
                    }
                    #endif
                    }
                } catch {
                    print("⚠️ [\(#function)] Failed to load photo data: \(error)")
                }
            } else {
                // User cleared the image
                cleanupPreviousImageIfNeeded(newPath: nil)
                selectedImage = nil
                imagePath = nil
            }
        }
    }

    #if os(iOS)
    func handleCameraImage(_ image: UIImage) {
        selectedImage = image
        do {
            let newPath = try PhotoStorageService.saveImage(image)
            // Clean up any intermediate image that might have been selected
            cleanupPreviousImageIfNeeded(newPath: newPath)
            imagePath = newPath
        } catch {
            #if DEBUG
            print("Error saving image: \(error)")
            #endif
            selectedImage = nil
        }
    }
    #endif

    // MARK: - Name Analysis

    func analyzeTextForNames(_ text: String) async {
        detectedStudentIDs.removeAll()
        guard !text.isEmpty else { return }

        let studentData = students.map { student in
            StudentData(
                id: student.id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname
            )
        }

        let result = await tagger.findStudentMatches(in: text, studentData: studentData)

        detectedStudentIDs = result.exact.union(result.fuzzy)

        let newAutoSelects = result.autoSelect.subtracting(selectedStudentIDs)
        if !newAutoSelects.isEmpty {
            selectedStudentIDs.formUnion(newAutoSelects)
        }
    }

    // MARK: - Initials Expansion

    func expandInitialsInBodyText() {
        let text = bodyText
        guard !text.isEmpty else { return }

        var initialsMap: [String: [Student]] = [:]
        for s in students {
            let first = s.firstName.trimmed()
            let last = s.lastName.trimmed()
            guard let fi = first.first, let li = last.first else { continue }
            let key = String(fi).lowercased() + String(li).lowercased()
            initialsMap[key, default: []].append(s)
        }

        let pattern = "\\b([A-Z])\\.?\\s*([A-Z])\\.?\\b"
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            print("⚠️ [\(#function)] Failed to create regex for initials expansion: \(error)")
            return
        }

        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        var newText = text
        var delta = 0

        regex.enumerateMatches(in: text, options: [], range: nsrange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3,
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text) else { return }

            let l1 = String(text[r1]).lowercased()
            let l2 = String(text[r2]).lowercased()
            let key = l1 + l2

            guard let candidates = initialsMap[key],
                  candidates.count == 1,
                  let student = candidates.first else { return }

            let first = student.firstName.trimmed()
            let lastInitial = student.lastName.trimmed().first.map { String($0).uppercased() } ?? ""
            let replacement = lastInitial.isEmpty ? first : "\(first) \(lastInitial)"

            let loc = match.range.location + delta
            let len = match.range.length
            let startIdx = newText.index(newText.startIndex, offsetBy: loc)
            let endIdx = newText.index(startIdx, offsetBy: len)
            newText.replaceSubrange(startIdx..<endIdx, with: replacement)
            delta += replacement.count - len
        }

        bodyText = newText
    }

    // MARK: - Context Description

    var contextDescription: String {
        switch context {
        case .general: return ".general"
        case .lesson: return ".lesson"
        case .work: return ".work"
        case .presentation: return ".presentation"
        case .attendance: return ".attendance"
        case .workCheckIn: return ".workCheckIn"
        case .workCompletion: return ".workCompletion"
        case .studentMeeting: return ".studentMeeting"
        case .projectSession: return ".projectSession"
        case .communityTopic: return ".communityTopic"
        case .reminder: return ".reminder"
        case .schoolDayOverride: return ".schoolDayOverride"
        }
    }
}
