//
//  ArchitectureMigrationSettingsView.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import SwiftUI

/// Settings view for architecture migration feature flags
/// Allows developers to toggle between old and new implementations
/// All flags are OFF by default for safety
struct ArchitectureMigrationSettingsView: View {
    @AppStorage("feature.protocolBasedServices") private var useProtocolBasedServices = false
    @AppStorage("feature.newDependencyInjection") private var useNewDependencyInjection = false
    @AppStorage("feature.newRepositoryPattern") private var useNewRepositoryPattern = false
    @AppStorage("feature.modernDIFramework") private var useModernDIFramework = false
    @AppStorage("feature.useModularCore") private var useModularCore = false
    
    private var anyEnabled: Bool {
        useProtocolBasedServices || useNewDependencyInjection || useNewRepositoryPattern || useModernDIFramework || useModularCore
    }
    
    private var enabledFlags: [String] {
        var flags: [String] = []
        if useProtocolBasedServices { flags.append("Protocol-Based Services") }
        if useNewDependencyInjection { flags.append("New Dependency Injection") }
        if useNewRepositoryPattern { flags.append("Repository Pattern") }
        if useModernDIFramework { flags.append("Modern DI Framework") }
        if useModularCore { flags.append("Modular Core") }
        return flags
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with warning
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Feature Flags")
                        .font(.headline)
                    Text("Toggle between old and new architecture implementations. All flags default to OFF for safety. See MIGRATION_STRATEGY.md for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Phase 1: Service Standardization
            FeatureFlagToggle(
                title: "Protocol-Based Services",
                description: "Phase 1: Use protocol-based service architecture with adapters for better testability",
                phase: "Phase 1",
                isOn: $useProtocolBasedServices
            )
            
            Divider()
            
            // Phase 2: Singleton Consolidation
            FeatureFlagToggle(
                title: "New Dependency Injection",
                description: "Phase 2: Use consolidated dependency injection via AppDependencies instead of .shared singletons",
                phase: "Phase 2",
                isOn: $useNewDependencyInjection
            )
            
            Divider()
            
            // Phase 3: Repository Pattern
            FeatureFlagToggle(
                title: "Repository Pattern",
                description: "Phase 3: Use repository pattern instead of direct @Query in views for better encapsulation",
                phase: "Phase 3",
                isOn: $useNewRepositoryPattern
            )
            
            Divider()
            
            // Phase 5: Modern DI Framework
            FeatureFlagToggle(
                title: "Modern DI Framework",
                description: "Phase 5: Use Swift Dependencies framework for dependency injection",
                phase: "Phase 5",
                isOn: $useModernDIFramework
            )
            
            Divider()
            
            // Phase 7: Modularization
            FeatureFlagToggle(
                title: "Modular Architecture",
                description: "Phase 7: Use modular Swift Package architecture (MariaCore, MariaServices, MariaUI)",
                phase: "Phase 7",
                isOn: $useModularCore
            )
            
            // Status summary
            if anyEnabled {
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("**Enabled flags:** \(enabledFlags.joined(separator: ", "))")
                        .font(.caption)
                }
                .padding(.top, 8)
            }
            
            // Reset button
            Divider()
            
            Button(role: .destructive) {
                useProtocolBasedServices = false
                useNewDependencyInjection = false
                useNewRepositoryPattern = false
                useModernDIFramework = false
                useModularCore = false
            } label: {
                Label("Reset All Flags to OFF", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}

/// Individual feature flag toggle with metadata
private struct FeatureFlagToggle: View {
    let title: String
    let description: String
    let phase: String
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        
                        Text(phase)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
            
            // Status indicator
            if isOn {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Active - Using new implementation")
                        .font(.caption2)
                }
                .foregroundStyle(.green)
            }
        }
    }
}

#Preview {
    ArchitectureMigrationSettingsView()
        .padding()
        .frame(maxWidth: 600)
}
