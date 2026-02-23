import SwiftUI

/// Displays validation errors before restore with detailed information
struct ValidationErrorView: View {
    let validation: BackupValidationService.ValidationResult
    let onDismiss: () -> Void
    let onProceedAnyway: (() -> Void)?
    
    @State private var showingDetails = false
    @State private var selectedError: BackupValidationService.ValidationError?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: validation.isValid ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(validation.isValid ? .green : .orange)
                
                VStack(alignment: .leading) {
                    Text("Backup Validation")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(validation.isValid ? "Ready to restore" : "\(validation.errors.count) issues found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // Errors List
            if !validation.errors.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Validation Errors")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(validation.errors) { error in
                                ValidationErrorRow(error: error)
                                    .onTapGesture {
                                        selectedError = error
                                        showingDetails = true
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            
            // Warnings
            if !validation.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Warnings")
                        .font(.headline)
                    
                    ForEach(validation.warnings) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(warning.message)
                                    .font(.body)
                                
                                if let recommendation = warning.recommendation {
                                    Text(recommendation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                if !validation.canProceed && onProceedAnyway != nil {
                    Button("Proceed Anyway") {
                        onProceedAnyway?()
                    }
                    .foregroundStyle(.orange)
                }
                
                if validation.canProceed {
                    Button("Continue") {
                        onProceedAnyway?()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct ValidationErrorRow: View {
    let error: BackupValidationService.ValidationError
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: severityIcon)
                .foregroundStyle(severityColor)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(error.entityType)
                    .font(.headline)
                
                Text(error.message)
                    .font(.body)
                
                if let field = error.field {
                    Text("Field: \(field)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(severityText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(severityColor.opacity(0.2))
                .foregroundStyle(severityColor)
                .cornerRadius(4)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var severityIcon: String {
        switch error.severity {
        case .critical: return "xmark.octagon.fill"
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    private var severityColor: Color {
        switch error.severity {
        case .critical: return .red
        case .error: return .orange
        case .warning: return .yellow
        }
    }
    
    private var severityText: String {
        switch error.severity {
        case .critical: return "CRITICAL"
        case .error: return "ERROR"
        case .warning: return "WARNING"
        }
    }
}
