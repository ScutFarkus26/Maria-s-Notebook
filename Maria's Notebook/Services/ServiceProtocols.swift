//
//  ServiceProtocols.swift
//  Maria's Notebook
//
//  Service Protocol Hierarchy
//

import CoreData

// MARK: - Base Service Protocol

/// Base protocol for all services in the application
/// Provides consistent initialization pattern with NSManagedObjectContext injection
protocol Service: AnyObject {
    /// The Core Data context used by this service
    var context: NSManagedObjectContext { get }

    /// Initialize service with an NSManagedObjectContext
    /// - Parameter context: The NSManagedObjectContext for data operations
    init(context: NSManagedObjectContext)
}

// MARK: - Lifecycle-Aware Services

/// Services that need to respond to application lifecycle events
protocol LifecycleAwareService: Service {
    func onAppWillResignActive() async
    func onAppDidBecomeActive() async
}

// MARK: - Cacheable Services

/// Services that maintain in-memory caches
protocol CacheableService: Service {
    func clearCache() async
}

// MARK: - Default Implementations

extension Service {
    func onAppWillResignActive() async {}
    func onAppDidBecomeActive() async {}
}

extension CacheableService {
    func clearCache() async {}
}
