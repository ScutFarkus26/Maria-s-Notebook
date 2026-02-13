//
//  FeatureFlags.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import SwiftUI

/// Feature flags for architecture migration
/// All flags default to OFF for safety - explicitly enable when testing
///
/// Usage in code:
/// ```swift
/// if FeatureFlags.shared.useProtocolBasedServices {
///     // Use new implementation
/// } else {
///     // Use legacy implementation
/// }
/// ```
///
/// Or in views with @AppStorage:
/// ```swift
/// @AppStorage("feature.protocolBasedServices") private var useProtocolBasedServices = false
/// ```
final class FeatureFlags {
    static let shared = FeatureFlags()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Phase 1: Service Standardization
    
    /// Use protocol-based service architecture with adapters
    /// Phase 1: Adds protocols to all services for better testability
    var useProtocolBasedServices: Bool {
        get { userDefaults.bool(forKey: "feature.protocolBasedServices") }
        set { userDefaults.set(newValue, forKey: "feature.protocolBasedServices") }
    }
    
    // MARK: - Phase 2: Singleton Consolidation
    
    /// Use consolidated dependency injection via AppDependencies
    /// Phase 2: Moves all .shared singletons into AppDependencies
    var useNewDependencyInjection: Bool {
        get { userDefaults.bool(forKey: "feature.newDependencyInjection") }
        set { userDefaults.set(newValue, forKey: "feature.newDependencyInjection") }
    }
    
    // MARK: - Phase 3: Repository Pattern
    
    /// Use repository pattern instead of direct @Query in views
    /// Phase 3: Encapsulates data access behind repositories
    var useNewRepositoryPattern: Bool {
        get { userDefaults.bool(forKey: "feature.newRepositoryPattern") }
        set { userDefaults.set(newValue, forKey: "feature.newRepositoryPattern") }
    }
    
    // MARK: - Phase 5: Modern DI Framework
    
    /// Use Swift Dependencies framework for dependency injection
    /// Phase 5: Replaces manual lazy initialization with @Dependency
    var useModernDIFramework: Bool {
        get { userDefaults.bool(forKey: "feature.modernDIFramework") }
        set { userDefaults.set(newValue, forKey: "feature.modernDIFramework") }
    }
    
    // MARK: - Phase 7: Modularization
    
    /// Use modular Swift Package architecture
    /// Phase 7: Breaks app into MariaCore, MariaServices, MariaUI packages
    var useModularCore: Bool {
        get { userDefaults.bool(forKey: "feature.useModularCore") }
        set { userDefaults.set(newValue, forKey: "feature.useModularCore") }
    }
    
    // MARK: - Utilities
    
    private init() {}
    
    /// Reset all flags to OFF (safe state)
    /// Use this to quickly return to legacy behavior
    func resetAll() {
        useProtocolBasedServices = false
        useNewDependencyInjection = false
        useNewRepositoryPattern = false
        useModernDIFramework = false
        useModularCore = false
    }
    
    /// Check if any migration flags are enabled
    var anyEnabled: Bool {
        useProtocolBasedServices ||
        useNewDependencyInjection ||
        useNewRepositoryPattern ||
        useModernDIFramework ||
        useModularCore
    }
    
    /// Get a summary of enabled flags
    var enabledFlags: [String] {
        var flags: [String] = []
        if useProtocolBasedServices { flags.append("Protocol-Based Services") }
        if useNewDependencyInjection { flags.append("New Dependency Injection") }
        if useNewRepositoryPattern { flags.append("Repository Pattern") }
        if useModernDIFramework { flags.append("Modern DI Framework") }
        if useModularCore { flags.append("Modular Core") }
        return flags
    }
}

// MARK: - Environment Key

struct FeatureFlagsKey: EnvironmentKey {
    static let defaultValue = FeatureFlags.shared
}

extension EnvironmentValues {
    var featureFlags: FeatureFlags {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}
