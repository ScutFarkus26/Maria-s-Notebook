// StudentDetailSheetModifiers.swift
// Sheet modifier helpers extracted from StudentDetailView

import SwiftUI

extension View {
    /// Applies standard sheet sizing for student detail sheets
    func studentDetailSheetSizing() -> some View {
        #if os(macOS)
        self
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
        #else
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
    
    /// Applies standard sizing for main student detail view
    func studentDetailMainSizing() -> some View {
        #if os(macOS)
        self
            .frame(minWidth: 860, minHeight: 640)
            .presentationSizingFitted()
        #else
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

