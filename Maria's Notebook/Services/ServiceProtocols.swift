//
//  ServiceProtocols.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Service Protocol Hierarchy
//

import SwiftData

// MARK: - Base Service Protocol

/// Base protocol for all services in the application
/// Provides consistent initialization pattern with ModelContext injection
protocol Service: AnyObject {
    /// The SwiftData context used by this service
    var context: ModelContext { get }
    
    /// Initialize service with a ModelContext
    /// - Parameter context: The SwiftData ModelContext for data operations
    init(context: ModelContext)
}

// MARK: - Lifecycle-Aware Services

/// Services that need to respond to application lifecycle events
/// Implement this when your service needs to perform actions on app state changes
protocol LifecycleAwareService: Service {
    /// Called when the app is about to resign active state
    /// Use this to save state, pause operations, or clean up resources
    func onAppWillResignActive() async
    
    /// Called when the app becomes active
    /// Use this to resume operations or refresh data
    func onAppDidBecomeActive() async
}

// MARK: - Cacheable Services

/// Services that maintain in-memory caches
/// Implement this when your service caches data that should be cleared under memory pressure
protocol CacheableService: Service {
    /// Clear all cached data
    /// Called during memory pressure or when cache needs to be invalidated
    func clearCache() async
}

// MARK: - Default Implementations

extension Service {
    /// Default implementation: services don't respond to lifecycle events
    /// Override in conforming types if lifecycle awareness is needed
    func onAppWillResignActive() async {
        // No-op by default
    }
    
    func onAppDidBecomeActive() async {
        // No-op by default
    }
}

extension CacheableService {
    /// Default implementation: no cache to clear
    /// Override in conforming types that maintain caches
    func clearCache() async {
        // No-op by default
    }
}

// MARK: - Service Registry

/// Registry for service protocols
/// Used during migration to track which services have been migrated to protocols
enum ServiceRegistry {
    /// Services that have been migrated to protocol-based architecture
    /// Add services here as they are migrated in Phase 1
    static let migratedServices: Set<String> = [
        // Phase 1 migrations will be added here
        // Example: "WorkCheckInService"
    ]
    
    /// Check if a service has been migrated to protocol-based architecture
    static func isMigrated(_ serviceName: String) -> Bool {
        migratedServices.contains(serviceName)
    }
}

// MARK: - Migration Notes

/*
 PHASE 1: Service Standardization
 
 This file defines the protocol hierarchy for service standardization.
 
 MIGRATION PATTERN:
 
 1. Create protocol for existing service:
    protocol WorkCheckInServiceProtocol: Service {
        func createCheckIn(for work: WorkModel, note: String?) async throws -> WorkCheckIn
    }
 
 2. Create adapter that wraps existing service:
    final class WorkCheckInServiceAdapter: WorkCheckInServiceProtocol {
        let context: ModelContext
        private let legacyService: WorkCheckInService
        
        required init(context: ModelContext) {
            self.context = context
            self.legacyService = WorkCheckInService(context: context)
        }
        
        func createCheckIn(for work: WorkModel, note: String?) async throws -> WorkCheckIn {
            return try await legacyService.createCheckIn(for: work, note: note)
        }
    }
 
 3. Update AppDependencies to use protocol:
    var workCheckInService: any WorkCheckInServiceProtocol {
        if FeatureFlags.shared.useProtocolBasedServices {
            return WorkCheckInServiceAdapter(context: modelContext)
        } else {
            return _workCheckInService ?? {
                let service = WorkCheckInService(context: modelContext)
                _workCheckInService = service
                return service
            }()
        }
    }
 
 4. Update usage sites to use protocol type:
    let service: any WorkCheckInServiceProtocol = dependencies.workCheckInService
 
 BENEFITS:
 - Better testability (easy to mock protocols)
 - Clear interface contracts
 - Easier to swap implementations
 - Type-safe dependency injection
 
 ROLLBACK:
 - Toggle FeatureFlags.useProtocolBasedServices = false
 - All code falls back to existing implementation
 */
