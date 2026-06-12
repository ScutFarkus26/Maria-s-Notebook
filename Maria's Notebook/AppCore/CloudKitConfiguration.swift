//
//  CloudKitConfiguration.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import Foundation

/// Handles CloudKit setup and configuration.
final class CloudKitConfiguration {
    
    // MARK: - CloudKit Container

    /// Returns a summary of CloudKit sync status
    static func getCloudKitStatus() -> CloudKitConfigurationService.Status {
        CloudKitConfigurationService.getStatus()
    }
}
