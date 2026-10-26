//
//  AttachmentRow+Details.swift
//  Cosmic Daybook
//
//  An attachment row's icon, the lines under its name, what it says when
//  its file can't be opened yet, and the Mac's "Open in <app>" name.
//

#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

extension AttachmentRow {
    // MARK: - Icon

    var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                .fill(fileTypeColor.opacity(UIConstants.OpacityConstants.light))

            Image(systemName: fileTypeIcon)
                .font(.system(size: 16))
                .foregroundStyle(fileTypeColor)
        }
    }

    private var fileTypeColor: Color {
        switch attachment.fileType {
        case "pdf": return .red
        case "pages": return .orange
        case "jpg", "jpeg", "png": return .blue
        default: return .gray
        }
    }

    private var fileTypeIcon: String {
        switch attachment.fileType {
        case "pdf": return "doc.fill"
        case "pages": return "doc.richtext.fill"
        case "jpg", "jpeg", "png": return "photo.fill"
        default: return "doc"
        }
    }

    // MARK: - Text under the name

    /// "605 KB · Added Oct 25", or "· Updated Oct 26" once the file, its name
    /// or its note has changed since it was attached.
    static func detailLine(for attachment: CDLessonAttachment, now: Date = Date()) -> String {
        guard let changed = changeLine(for: attachment, now: now) else { return attachment.fileSizeFormatted }
        return "\(attachment.fileSizeFormatted) · \(changed)"
    }

    /// "Added Oct 25" or "Updated Oct 26" (with the year when it isn't this
    /// year's), from `lastChanged`; nil for a record with no dates.
    static func changeLine(
        for attachment: CDLessonAttachment, now: Date = Date(), calendar: Calendar = .current
    ) -> String? {
        guard let changed = attachment.lastChanged else { return nil }
        // The convenience init stamps both with one instant; a later change
        // moves `modifiedAt` on.
        let isUpdate: Bool = {
            guard let modified = attachment.modifiedAt, let attached = attachment.attachedAt else { return false }
            return modified.timeIntervalSince(attached) >= 1
        }()
        let formatter = calendar.isDate(changed, equalTo: now, toGranularity: .year)
            ? DateFormatters.shortMonthDay
            : DateFormatters.mediumDate
        return "\(isUpdate ? "Updated" : "Added") \(formatter.string(from: changed))"
    }

    /// The note (where the file came from), trimmed; nil when there is none.
    static func noteLine(for attachment: CDLessonAttachment) -> String? {
        let note = attachment.notes.trimmed()
        return note.isEmpty ? nil : note
    }

    // MARK: - A file that can't be opened

    /// What to say when the file couldn't be made ready to open or share:
    /// that iCloud is still sending it to this device (`stillInICloud`), or
    /// that it isn't there at all.
    static func unavailableMessage(stillInICloud: Bool) -> String {
        stillInICloud
            ? "This file is still downloading from iCloud. Try again in a moment."
            : "Couldn't find this attachment's file. It may have been moved or deleted."
    }

    /// The same for the file at `url` (nil when none was found): still in
    /// iCloud when the file or its placeholder is there but its bytes didn't
    /// come down in time, missing when nothing is there.
    static func unavailableMessage(for url: URL?) -> String {
        unavailableMessage(stillInICloud: url.map(UbiquitousFile.isAvailable) ?? false)
    }

    #if os(macOS)
    // MARK: - Open in <app>

    /// The name of the app that opens files of this kind ("Preview"), looked
    /// up once per kind.
    static func defaultAppName(forFileType fileType: String) -> String? {
        let key = fileType.lowercased()
        if let known = appNames[key] { return known }
        let name = UTType(filenameExtension: key)
            .flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        appNames[key] = name
        return name
    }

    private static var appNames: [String: String?] = [:]
    #endif
}
