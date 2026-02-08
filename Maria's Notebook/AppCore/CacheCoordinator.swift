import Foundation
import Combine
import OSLog

private let logger = Logger.cache

/// Centralized cache lifecycle coordinator for Phase 7 state management.
///
/// This coordinator provides unified cache management across the application,
/// replacing manual cache invalidation with reactive patterns.
///
/// **Before (scattered cache management):**
/// ```swift
/// var date: Date {
///     didSet {
///         cacheManager.invalidate()
///         reload()
///     }
/// }
/// ```
///
/// **After (centralized coordination):**
/// ```swift
/// coordinator.register(todayCache, key: "today")
/// coordinator.invalidate(key: "today")  // Or invalidateAll()
/// ```
@MainActor
final class CacheCoordinator: ObservableObject {
    
    // MARK: - Cache Registry
    
    private var caches: [String: any Caching] = [:]
    private var metrics: [String: CacheMetrics] = [:]
    
    // MARK: - Invalidation Publisher
    
    private let invalidationSubject = PassthroughSubject<CacheInvalidationEvent, Never>()
    
    /// Publisher that emits cache invalidation events
    var invalidationPublisher: AnyPublisher<CacheInvalidationEvent, Never> {
        invalidationSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Registration
    
    /// Register a cache with the coordinator
    func register<C: Caching>(_ cache: C, key: String) {
        caches[key] = cache
        metrics[key] = CacheMetrics(key: key)
        
        logger.info("Registered cache '\(key)'")
    }
    
    /// Unregister a cache
    func unregister(key: String) {
        caches.removeValue(forKey: key)
        metrics.removeValue(forKey: key)
        
        logger.info("Unregistered cache '\(key)'")
    }
    
    // MARK: - Invalidation
    
    /// Invalidate a specific cache by key
    func invalidate(key: String) {
        guard let cache = caches[key] else {
            logger.error("Warning - cache '\(key)' not found")
            return
        }
        
        cache.invalidate()
        metrics[key]?.recordInvalidation()
        
        invalidationSubject.send(.specific(key))
        
        logger.info("Invalidated cache '\(key)'")
    }
    
    /// Invalidate all registered caches
    func invalidateAll() {
        for (key, cache) in caches {
            cache.invalidate()
            metrics[key]?.recordInvalidation()
        }
        
        invalidationSubject.send(.all)
        
        logger.info("Invalidated all caches (\(self.caches.count) total)")
    }
    
    /// Invalidate caches matching a pattern
    func invalidateMatching(pattern: String) {
        let matchingKeys = caches.keys.filter { $0.contains(pattern) }
        
        for key in matchingKeys {
            invalidate(key: key)
        }
        
        invalidationSubject.send(.pattern(pattern))
        
        logger.info("Invalidated \(matchingKeys.count) caches matching '\(pattern)'")
    }
    
    // MARK: - Metrics
    
    /// Get metrics for a specific cache
    func metrics(for key: String) -> CacheMetrics? {
        return metrics[key]
    }
    
    /// Get all cache metrics
    func allMetrics() -> [CacheMetrics] {
        return Array(metrics.values).sorted { $0.key < $1.key }
    }
    
    /// Get summary of all cache performance
    func performanceSummary() -> String {
        var lines = ["Cache Performance Summary:"]
        lines.append("Total caches: \(caches.count)")
        lines.append("")
        
        for metric in allMetrics() {
            lines.append("[\(metric.key)]")
            lines.append("  Hits: \(metric.hitCount) | Misses: \(metric.missCount)")
            lines.append("  Hit Rate: \(String(format: "%.1f%%", metric.hitRate * 100))")
            lines.append("  Invalidations: \(metric.invalidationCount)")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Lifecycle
    
    /// Clean up all caches and reset metrics
    func reset() {
        invalidateAll()
        caches.removeAll()
        metrics.removeAll()
        
        logger.info("Reset complete")
    }
}

// MARK: - Caching Protocol

/// Protocol that all cacheable components must conform to
protocol Caching {
    /// Invalidate this cache
    func invalidate()
    
    /// Check if cache has data
    var hasData: Bool { get }
}

// MARK: - Cache Invalidation Event

enum CacheInvalidationEvent: Equatable {
    case specific(String)
    case pattern(String)
    case all
}

// MARK: - Cache Metrics

struct CacheMetrics: Identifiable {
    let id = UUID()
    let key: String
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0
    private(set) var invalidationCount: Int = 0
    private(set) var lastInvalidation: Date?
    
    var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
    
    mutating func recordHit() {
        hitCount += 1
    }
    
    mutating func recordMiss() {
        missCount += 1
    }
    
    mutating func recordInvalidation() {
        invalidationCount += 1
        lastInvalidation = .now
    }
}

// MARK: - Reactive Cache Base Class

/// Base class for caches that support reactive invalidation
@MainActor
class ReactiveCache: Caching, ObservableObject {
    @Published private(set) var hasData: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let coordinator: CacheCoordinator?
    private let key: String
    
    init(coordinator: CacheCoordinator? = nil, key: String) {
        self.coordinator = coordinator
        self.key = key
        
        // Register with coordinator if provided
        coordinator?.register(self, key: key)
        
        // Subscribe to invalidation events
        coordinator?.invalidationPublisher
            .sink { [weak self] event in
                self?.handleInvalidation(event)
            }
            .store(in: &cancellables)
    }
    
    func invalidate() {
        hasData = false
        onInvalidate()
    }
    
    /// Override this method to perform custom invalidation logic
    func onInvalidate() {
        // Subclasses override
    }
    
    private func handleInvalidation(_ event: CacheInvalidationEvent) {
        switch event {
        case .specific(let eventKey):
            if eventKey == key {
                invalidate()
            }
        case .pattern(let pattern):
            if key.contains(pattern) {
                invalidate()
            }
        case .all:
            invalidate()
        }
    }
    
    deinit {
        let coordinator = self.coordinator
        let key = self.key
        Task { @MainActor in
            coordinator?.unregister(key: key)
        }
    }
}

// MARK: - Example Usage

/*
 Example: TodayViewModel with reactive cache
 
 @MainActor
 final class TodayViewModel: ObservableObject {
     private let cacheCoordinator: CacheCoordinator
     private let todayCache: TodayDataCache
     
     @Published var date: Date = .now
     @Published var filter: LevelFilter = .all
     @Published private(set) var lessons: [StudentLesson] = []
     
     private var cancellables = Set<AnyCancellable>()
     
     init(cacheCoordinator: CacheCoordinator) {
         self.cacheCoordinator = cacheCoordinator
         self.todayCache = TodayDataCache(coordinator: cacheCoordinator, key: "today")
         
         setupReactiveInvalidation()
     }
     
     private func setupReactiveInvalidation() {
         // Automatically reload when inputs change
         Publishers.CombineLatest($date, $filter)
             .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
             .sink { [weak self] _, _ in
                 self?.cacheCoordinator.invalidate(key: "today")
                 self?.reload()
             }
             .store(in: &cancellables)
     }
     
     private func reload() {
         // Reload implementation
     }
 }
 
 // Custom cache implementation
 class TodayDataCache: ReactiveCache {
     private var cachedLessons: [StudentLesson] = []
     
     override func onInvalidate() {
         cachedLessons = []
     }
     
     func getLessons() -> [StudentLesson]? {
         guard hasData else { return nil }
         return cachedLessons
     }
     
     func setLessons(_ lessons: [StudentLesson]) {
         cachedLessons = lessons
         hasData = true
     }
 }
 */

// MARK: - Debug View

#if DEBUG
import SwiftUI

struct CacheDebugView: View {
    @ObservedObject var coordinator: CacheCoordinator
    @State private var selectedCache: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cache Coordinator Debug")
                .font(.title)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(coordinator.allMetrics()) { metric in
                        CacheMetricRow(metric: metric, coordinator: coordinator)
                    }
                }
                .padding()
            }
            
            HStack {
                Button("Invalidate All") {
                    coordinator.invalidateAll()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Reset") {
                    coordinator.reset()
                }
                .buttonStyle(.bordered)
            }
            
            Text(coordinator.performanceSummary())
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
}

struct CacheMetricRow: View {
    let metric: CacheMetrics
    let coordinator: CacheCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.key)
                    .font(.headline)
                
                Spacer()
                
                Button("Invalidate") {
                    coordinator.invalidate(key: metric.key)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack {
                Label("\(metric.hitCount)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Label("\(metric.missCount)", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                
                Text("Hit Rate: \(String(format: "%.1f%%", metric.hitRate * 100))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let lastInvalidation = metric.lastInvalidation {
                    Text("Last: \(lastInvalidation, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}
#endif
