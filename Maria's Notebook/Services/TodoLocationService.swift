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
        return await withCheckedContinuation { continuation in
            let delegate = LocationDelegate { location in
                continuation.resume(returning: location)
            }
            
            let manager = CLLocationManager()
            manager.delegate = delegate
            manager.requestLocation()
            
            // Keep delegate alive
            withExtendedLifetime(delegate) {}
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            handleRegionEvent(region: region, isEntry: true)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            handleRegionEvent(region: region, isEntry: false)
        }
    }
    
    private func handleRegionEvent(region: CLRegion, isEntry: Bool) {
        let todoID = region.identifier.replacingOccurrences(of: "todo-", with: "")
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
private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let completion: (CLLocation?) -> Void
    
    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completion(locations.first)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion(nil)
    }
}
