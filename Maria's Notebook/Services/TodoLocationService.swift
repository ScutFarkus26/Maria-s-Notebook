import Foundation
import CoreLocation
import UserNotifications
import SwiftData

/// Service for managing location-based todo reminders
@MainActor
class TodoLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = TodoLocationService()
    
    private let locationManager = CLLocationManager()
    private var monitoredTodos: [String: TodoItem] = [:] // todoID -> TodoItem
    private var activeLocationRequests: [UUID: (manager: CLLocationManager, delegate: LocationDelegate)] = [:]
    
    private override init() {
        super.init()
        locationManager.delegate = self
    }
    
    /// Request location permissions
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization() // For background geofencing
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() -> CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }
    
    /// Set up geofence for a todo item
    func setupGeofence(for todo: TodoItem) {
        guard let latitude = todo.locationLatitude,
              let longitude = todo.locationLongitude else {
            return
        }
        
        // Remove existing geofence if any
        removeGeofence(for: todo)
        
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: todo.locationRadius,
            identifier: "todo-\(todo.id.uuidString)"
        )
        
        region.notifyOnEntry = todo.notifyOnEntry
        region.notifyOnExit = todo.notifyOnExit
        
        locationManager.startMonitoring(for: region)
        monitoredTodos[todo.id.uuidString] = todo
    }
    
    /// Remove geofence for a todo item
    func removeGeofence(for todo: TodoItem) {
        let identifier = "todo-\(todo.id.uuidString)"
        
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
        }
        
        monitoredTodos.removeValue(forKey: todo.id.uuidString)
    }
    
    /// Get current location
    func getCurrentLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            let requestID = UUID()
            let manager = CLLocationManager()
            let delegate = LocationDelegate { [weak self] location in
                guard let self else {
                    continuation.resume(returning: location)
                    return
                }
                self.activeLocationRequests.removeValue(forKey: requestID)
                continuation.resume(returning: location)
            }

            manager.delegate = delegate
            activeLocationRequests[requestID] = (manager, delegate)
            manager.requestLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in
            handleRegionEvent(regionIdentifier: identifier, isEntry: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in
            handleRegionEvent(regionIdentifier: identifier, isEntry: false)
        }
    }

    private func handleRegionEvent(regionIdentifier: String, isEntry: Bool) {
        let todoID = regionIdentifier.replacingOccurrences(of: "todo-", with: "")
        guard let todo = monitoredTodos[todoID] else {
            return
        }
        
        // Send notification
        let content = UNMutableNotificationContent()
        content.title = isEntry ? "Arrived at \(todo.locationName ?? "location")" : "Leaving \(todo.locationName ?? "location")"
        content.body = todo.title
        content.sound = .default
        content.userInfo = ["todoID": todo.id.uuidString]
        
        let request = UNNotificationRequest(
            identifier: "location-\(todo.id.uuidString)-\(isEntry ? "entry" : "exit")",
            content: content,
            trigger: nil // Immediate notification
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending location notification: \(error)")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error)")
    }
}

// Helper delegate for one-time location requests
@MainActor
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    private var completion: ((CLLocation?) -> Void)?
    
    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
    }

    private func complete(with location: CLLocation?) {
        guard let completion else { return }
        self.completion = nil
        completion(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        complete(with: locations.first)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        complete(with: nil)
    }
}
