// TodoLocationPickerView.swift
// Map-based location picker for todo location reminders

import OSLog
import SwiftUI
import MapKit

struct TodoLocationPickerView: View {
    private static let logger = Logger.todos
    @Binding var locationName: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search for a place", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                #if os(iOS)
                .background(Color(.systemBackground))
                #else
                .background(Color(nsColor: .controlBackgroundColor))
                #endif
                
                Divider()
                
                ZStack(alignment: .bottom) {
                    // Map
                    Map(position: $cameraPosition, interactionModes: .all) {
                        if let coord = selectedCoordinate {
                            Marker(locationName.isEmpty ? "Selected" : locationName, coordinate: coord)
                                .tint(.red)
                        }
                        
                        ForEach(searchResults, id: \.self) { item in
                            Marker(item.name ?? "Unknown", coordinate: item.location.coordinate)
                                .tint(.blue)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .onMapCameraChange(frequency: .onEnd) { _ in
                        // Allow tapping on search results to select them
                    }
                    
                    // Search results overlay
                    if !searchResults.isEmpty {
                        searchResultsList
                    }
                    
                    // Selected location info
                    if let coord = selectedCoordinate {
                        selectedLocationBar(coord)
                    }
                }
            }
            .navigationTitle("Choose Location")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let coord = selectedCoordinate {
                            latitude = coord.latitude
                            longitude = coord.longitude
                        }
                        dismiss()
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
            .onAppear {
                if let lat = latitude, let lon = longitude {
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    selectedCoordinate = coord
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    ))
                }
            }
        }
    }
    
    // MARK: - Search Results List
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        selectMapItem(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .font(AppTheme.ScaledFont.bodySemibold)
                                    .foregroundStyle(.primary)
                                
                                if let address = item.address?.shortAddress {
                                    Text(address)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.leading, 52)
                }
            }
        }
        .frame(maxHeight: 200)
        #if os(iOS)
        .background(.ultraThinMaterial)
        #else
        .background(.regularMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, selectedCoordinate != nil ? 80 : 16)
    }
    
    // MARK: - Selected Location Bar
    
    private func selectedLocationBar(_ coord: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20))
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(locationName.isEmpty ? "Selected Location" : locationName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                selectedCoordinate = nil
                locationName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(iOS)
        .background(.ultraThinMaterial)
        #else
        .background(.regularMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Search
    
    private func performSearch() {
        guard !searchText.trimmed().isEmpty else { return }
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            guard let response else {
                if let error {
                    Self.logger.error("[\(#function)] Search failed: \(error)")
                }
                return
            }
            searchResults = response.mapItems
        }
    }
    
    private func selectMapItem(_ item: MKMapItem) {
        let coord = item.location.coordinate
        selectedCoordinate = coord
        locationName = item.name ?? ""
        searchResults = []
        searchText = ""
        
        adaptiveWithAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }
}
