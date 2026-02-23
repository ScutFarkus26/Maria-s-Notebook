import SwiftUI
import Charts
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

/// Telemetry dashboard for backup/restore statistics and monitoring
struct TelemetryDashboardView: View {
    let telemetry: BackupTelemetryService
    @State private var selectedPeriod: Period = .week
    @State private var report: BackupTelemetryService.TelemetryReport?
    
    enum Period: String, CaseIterable {
        case day = "24 Hours"
        case week = "7 Days"
        case month = "30 Days"
        case all = "All Time"
        
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .all: return 365 * 10  // 10 years
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Backup Telemetry")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Performance metrics and statistics")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Period Selector
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(Period.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                
                if let report = report {
                    // Success Rate Cards
                    HStack(spacing: 16) {
                        MetricCard(
                            title: "Backup Success Rate",
                            value: "\(Int(report.metrics.backupSuccessRate))%",
                            subtitle: "\(report.successfulBackups)/\(report.totalBackups) successful",
                            color: successRateColor(report.metrics.backupSuccessRate),
                            icon: "arrow.up.doc.fill"
                        )
                        
                        MetricCard(
                            title: "Restore Success Rate",
                            value: "\(Int(report.metrics.restoreSuccessRate))%",
                            subtitle: "\(report.successfulRestores)/\(report.totalRestores) successful",
                            color: successRateColor(report.metrics.restoreSuccessRate),
                            icon: "arrow.down.doc.fill"
                        )
                    }
                    
                    // Performance Metrics
                    HStack(spacing: 16) {
                        MetricCard(
                            title: "Avg Backup Time",
                            value: report.metrics.formattedAvgBackupTime,
                            subtitle: "Per backup operation",
                            color: .blue,
                            icon: "clock.fill"
                        )
                        
                        MetricCard(
                            title: "Avg Restore Time",
                            value: report.metrics.formattedAvgRestoreTime,
                            subtitle: "Per restore operation",
                            color: .purple,
                            icon: "clock.fill"
                        )
                        
                        MetricCard(
                            title: "Avg File Size",
                            value: report.metrics.formattedAvgFileSize,
                            subtitle: "Per backup file",
                            color: .orange,
                            icon: "doc.fill"
                        )
                    }
                    
                    // Operation Timeline
                    if !telemetry.recentEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Operation Timeline")
                                .font(.headline)
                            
                            EventTimelineChart(events: filteredEvents)
                                .frame(height: 200)
                        }
                        .padding()
                        .background(Color.controlBackgroundColor())
                        .cornerRadius(8)
                    }
                    
                    // Top Errors
                    if !report.topErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Errors")
                                .font(.headline)
                            
                            ForEach(Array(report.topErrors.enumerated()), id: \.offset) { index, errorTuple in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    
                                    Text(errorTuple.error)
                                        .font(.body)
                                    
                                    Spacer()
                                    
                                    Text("\(errorTuple.count)×")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.controlBackgroundColor())
                        .cornerRadius(8)
                    }
                    
                    // Device Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Information")
                            .font(.headline)
                        
                        Grid(alignment: .leading) {
                            GridRow {
                                Text("Model:")
                                    .foregroundStyle(.secondary)
                                Text(report.deviceInfo.model)
                            }
                            GridRow {
                                Text("OS Version:")
                                    .foregroundStyle(.secondary)
                                Text(report.deviceInfo.osVersion)
                            }
                            GridRow {
                                Text("App Version:")
                                    .foregroundStyle(.secondary)
                                Text("\(report.deviceInfo.appVersion) (\(report.deviceInfo.appBuild))")
                            }
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(Color.controlBackgroundColor())
                    .cornerRadius(8)
                }
                
                // Actions
                HStack {
                    Button("Export Data") {
                        exportTelemetryData()
                    }
                    
                    Button("Clear Data") {
                        telemetry.clearAllData()
                        updateReport()
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .onAppear {
            updateReport()
        }
        .onChange(of: selectedPeriod) {
            updateReport()
        }
    }
    
    private var filteredEvents: [BackupTelemetryService.TelemetryEvent] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: Date()) ?? Date()
        return telemetry.recentEvents.filter { $0.timestamp >= cutoffDate }
    }
    
    private func updateReport() {
        report = telemetry.generateReportForLastDays(selectedPeriod.days)
    }
    
    private func successRateColor(_ rate: Double) -> Color {
        if rate >= Double(BackupConstants.telemetrySuccessThreshold) { return .green }
        if rate >= Double(BackupConstants.telemetryWarningThreshold) { return .orange }
        return .red
    }
    
    private func exportTelemetryData() {
        #if os(macOS)
        do {
            let data = try telemetry.exportData()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "backup-telemetry.json"
            panel.allowedContentTypes = [.json]

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try data.write(to: url, options: .atomic)
                    } catch {
                        Logger.backup.error("Failed to write telemetry export: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            Logger.backup.error("Failed to export telemetry: \(error)")
        }
        #endif
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.headline)
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.controlBackgroundColor())
        .cornerRadius(8)
    }
}

@available(macOS 13.0, *)
struct EventTimelineChart: View {
    let events: [BackupTelemetryService.TelemetryEvent]
    
    var body: some View {
        Chart {
            ForEach(events) { event in
                BarMark(
                    x: .value("Date", event.timestamp, unit: .day),
                    y: .value("Count", 1)
                )
                .foregroundStyle(by: .value("Type", event.operation.rawValue))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
    }
}

#Preview {
    TelemetryDashboardView(telemetry: BackupTelemetryService())
        .frame(width: 800, height: 600)
}
