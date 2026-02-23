// BackupNotificationService.swift
// Handles backup-related notifications and alerts

import Foundation
import UserNotifications
import OSLog
#if os(macOS)
import AppKit
#endif

/// Service for managing backup-related notifications
@Observable
@MainActor
public final class BackupNotificationService {
    
    // MARK: - Dependencies
    
    private weak var autoBackupManager: AutoBackupManager?

    // MARK: - Types

    public enum NotificationType: String, CaseIterable, Sendable {
        case autoBackupComplete = "Auto-backup completed"
        case autoBackupFailed = "Auto-backup failed"
        case scheduledBackupComplete = "Scheduled backup completed"
        case backupHealthWarning = "Backup health warning"
        case backupIntegrityIssue = "Backup integrity issue"

        public var systemImage: String {
            switch self {
            case .autoBackupComplete, .scheduledBackupComplete:
                return "checkmark.circle.fill"
            case .autoBackupFailed, .backupIntegrityIssue:
                return "exclamationmark.triangle.fill"
            case .backupHealthWarning:
                return "exclamationmark.circle.fill"
            }
        }

        public var isError: Bool {
            switch self {
            case .autoBackupFailed, .backupIntegrityIssue:
                return true
            default:
                return false
            }
        }
    }

    public struct BackupNotification: Identifiable, Sendable {
        public let id: UUID
        public let type: NotificationType
        public let title: String
        public let message: String
        public let timestamp: Date
        public let backupURL: URL?
        public let isRead: Bool

        public init(
            type: NotificationType,
            title: String,
            message: String,
            backupURL: URL? = nil
        ) {
            self.id = UUID()
            self.type = type
            self.title = title
            self.message = message
            self.timestamp = Date()
            self.backupURL = backupURL
            self.isRead = false
        }
    }

    // MARK: - Settings

    public var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "BackupNotifications.enabled")
        }
    }

    public var showSuccessNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showSuccessNotifications, forKey: "BackupNotifications.showSuccess")
        }
    }

    public var showFailureNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showFailureNotifications, forKey: "BackupNotifications.showFailure")
        }
    }

    public var showHealthWarnings: Bool {
        didSet {
            UserDefaults.standard.set(showHealthWarnings, forKey: "BackupNotifications.showHealthWarnings")
        }
    }

    // MARK: - State

    private(set) var recentNotifications: [BackupNotification] = []
    private(set) var unreadCount: Int = 0

    // MARK: - Initialization

    public init() {
        // Load settings from UserDefaults
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "BackupNotifications.enabled") as? Bool ?? true
        self.showSuccessNotifications = UserDefaults.standard.object(forKey: "BackupNotifications.showSuccess") as? Bool ?? false
        self.showFailureNotifications = UserDefaults.standard.object(forKey: "BackupNotifications.showFailure") as? Bool ?? true
        self.showHealthWarnings = UserDefaults.standard.object(forKey: "BackupNotifications.showHealthWarnings") as? Bool ?? true
    }
    
    /// Configures the service to observe the given AutoBackupManager
    func configure(with autoBackupManager: AutoBackupManager) {
        self.autoBackupManager = autoBackupManager
        setupObservers()
    }

    // MARK: - Public API

    /// Requests notification permission from the user
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            Logger.backup.error("Failed to request permission: \(error)")
            return false
        }
    }

    /// Sends a backup completion notification
    func notifyBackupComplete(
        type: AutoBackupManager.BackupTrigger,
        url: URL,
        fileSize: Int64?
    ) {
        guard notificationsEnabled else { return }
        guard showSuccessNotifications else { return }

        let notificationType: NotificationType
        let title: String

        switch type {
        case .appQuit:
            notificationType = .autoBackupComplete
            title = "Auto-Backup Complete"
        case .scheduled:
            notificationType = .scheduledBackupComplete
            title = "Scheduled Backup Complete"
        case .preDestructive:
            notificationType = .autoBackupComplete
            title = "Safety Backup Created"
        case .manual:
            return // Don't notify for manual backups
        }

        let sizeString: String
        if let size = fileSize {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            sizeString = " (\(formatter.string(fromByteCount: size)))"
        } else {
            sizeString = ""
        }

        let message = "Backup saved to \(url.lastPathComponent)\(sizeString)"

        let notification = BackupNotification(
            type: notificationType,
            title: title,
            message: message,
            backupURL: url
        )

        addNotification(notification)
        sendSystemNotification(notification)
    }

    /// Sends a backup failure notification
    func notifyBackupFailed(
        type: AutoBackupManager.BackupTrigger,
        error: Error
    ) {
        guard notificationsEnabled else { return }
        guard showFailureNotifications else { return }

        let title: String
        switch type {
        case .appQuit:
            title = "Auto-Backup Failed"
        case .scheduled:
            title = "Scheduled Backup Failed"
        case .preDestructive:
            title = "Safety Backup Failed"
        case .manual:
            return
        }

        let notification = BackupNotification(
            type: .autoBackupFailed,
            title: title,
            message: error.localizedDescription
        )

        addNotification(notification)
        sendSystemNotification(notification)
    }

    /// Sends a backup health warning notification
    public func notifyBackupHealthWarning(message: String) {
        guard notificationsEnabled else { return }
        guard showHealthWarnings else { return }

        let notification = BackupNotification(
            type: .backupHealthWarning,
            title: "Backup Health Warning",
            message: message
        )

        addNotification(notification)
        sendSystemNotification(notification)
    }

    /// Sends a backup integrity issue notification
    public func notifyIntegrityIssue(fileName: String, issue: String) {
        guard notificationsEnabled else { return }

        let notification = BackupNotification(
            type: .backupIntegrityIssue,
            title: "Backup Integrity Issue",
            message: "\(fileName): \(issue)"
        )

        addNotification(notification)
        sendSystemNotification(notification)
    }

    /// Marks all notifications as read
    public func markAllAsRead() {
        recentNotifications = recentNotifications.map { notification in
            BackupNotification(
                type: notification.type,
                title: notification.title,
                message: notification.message,
                backupURL: notification.backupURL
            )
        }
        unreadCount = 0
    }

    /// Clears all notifications
    public func clearNotifications() {
        recentNotifications = []
        unreadCount = 0
    }

    // MARK: - Private Helpers

    private func setupObservers() {
        // Observe backup events from AutoBackupManager
        guard let autoBackupManager else { return }
        
        Task { @MainActor in
            var lastEvent: AutoBackupManager.BackupEvent?
            
            while !Task.isCancelled {
                // Check if there's a new event
                if let event = autoBackupManager.lastBackupEvent, event.timestamp != lastEvent?.timestamp {
                    lastEvent = event
                    
                    switch event.result {
                    case .success(let url):
                        let fileSize: Int64?
                        do {
                            fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
                        } catch {
                            print("⚠️ [Backup:observeBackupEvents] Failed to get file size for \(url.lastPathComponent): \(error)")
                            fileSize = nil
                        }
                        self.notifyBackupComplete(type: event.trigger, url: url, fileSize: fileSize)
                        
                    case .failure(let error):
                        self.notifyBackupFailed(type: event.trigger, error: error)
                    }
                }
                
                // Check periodically for new events
                do {
                    try await Task.sleep(for: .seconds(0.5))
                } catch {
                    print("⚠️ [Backup:observeBackupEvents] Task sleep interrupted: \(error)")
                    break
                }
            }
        }
    }

    private func addNotification(_ notification: BackupNotification) {
        recentNotifications.insert(notification, at: 0)

        // Keep only last 50 notifications
        if recentNotifications.count > 50 {
            recentNotifications = Array(recentNotifications.prefix(50))
        }

        if !notification.isRead {
            unreadCount += 1
        }
    }

    private func sendSystemNotification(_ notification: BackupNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = notification.type.isError ? .defaultCritical : .default

        // Add category for actions
        content.categoryIdentifier = "BACKUP_NOTIFICATION"

        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.backup.error("Failed to send notification: \(error)")
            }
        }

        #if os(macOS)
        // Also show in-app notification badge
        updateDockBadge()
        #endif
    }

    #if os(macOS)
    private func updateDockBadge() {
        if unreadCount > 0 {
            NSApp.dockTile.badgeLabel = "\(unreadCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }
    #endif
}

// MARK: - Backup Health Badge View Model

extension BackupNotificationService {

    /// View model for displaying backup health status in the UI
    public struct BackupHealthBadge {
        public let isHealthy: Bool
        public let warningCount: Int
        public let lastBackupDate: Date?
        public let message: String?

        public var badgeColor: String {
            if !isHealthy { return "red" }
            if warningCount > 0 { return "orange" }
            return "green"
        }

        public var systemImage: String {
            if !isHealthy { return "xmark.shield.fill" }
            if warningCount > 0 { return "exclamationmark.triangle.fill" }
            return "checkmark.shield.fill"
        }

        public var statusText: String {
            if !isHealthy { return "Issues Detected" }
            if warningCount > 0 { return "\(warningCount) Warning(s)" }
            return "Healthy"
        }
    }

    /// Gets the current backup health badge
    public func getHealthBadge() async -> BackupHealthBadge {
        let monitor = BackupIntegrityMonitor()
        let health = await monitor.quickHealthCheck()

        let status = BackupVerification.getBackupStatus()

        return BackupHealthBadge(
            isHealthy: health.isHealthy,
            warningCount: health.isHealthy ? 0 : 1,
            lastBackupDate: status.lastBackupDate,
            message: health.message
        )
    }
}
