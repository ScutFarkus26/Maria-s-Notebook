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
    
    /// Returns the CloudKit container identifier from entitlements
    /// This must match the container ID in the entitlements file
    static func getCloudKitContainerID() -> String? {
        CloudKitConfigurationService.getContainerID()
    }

    /// Returns a summary of CloudKit sync status
    static func getCloudKitStatus() -> (enabled: Bool, active: Bool, containerID: String) {
        let status = CloudKitConfigurationService.getStatus()
        return (enabled: status.enabled, active: status.active, containerID: status.containerID)
    }
}
