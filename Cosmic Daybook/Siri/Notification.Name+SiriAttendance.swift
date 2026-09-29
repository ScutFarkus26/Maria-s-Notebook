//
//  Notification.Name+SiriAttendance.swift
//  Cosmic Daybook
//
//  Shared with Daybook Assistant, which compiles this file by path.
//

import Foundation

extension Notification.Name {
    /// Posted after a Siri intent saves attendance, so an open roll redraws.
    static let attendanceChangedBySiri = Notification.Name("attendanceChangedBySiri")
}
