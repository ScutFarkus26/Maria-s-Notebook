import Foundation

// MARK: - API Usage Tracker

/// Tracks Claude API call usage including token counts and estimated cost.
/// Stores entries in UserDefaults as JSON.
@Observable @MainActor
final class APIUsageTracker {
    static let shared = APIUsageTracker()

    struct UsageEntry: Codable, Sendable {
        let date: Date
        let model: String
        let inputTokens: Int?
        let outputTokens: Int?
        let estimatedCost: Double?
    }

    private let maxEntries = 200
    private let storageKey = "APIUsage.entries"

    private(set) var entries: [UsageEntry] = []

    var totalEstimatedCost: Double {
        entries.reduce(0) { $0 + ($1.estimatedCost ?? 0) }
    }

    var totalInputTokens: Int {
        entries.reduce(0) { $0 + ($1.inputTokens ?? 0) }
    }

    var totalOutputTokens: Int {
        entries.reduce(0) { $0 + ($1.outputTokens ?? 0) }
    }

    var todayCallCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.count
    }

    var thisMonthCallCount: Int {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        guard let startOfMonth = Calendar.current.date(from: components) else { return 0 }
        return entries.filter { $0.date >= startOfMonth }.count
    }

    init() {
        loadEntries()
    }

    func logUsage(model: String, inputTokens: Int?, outputTokens: Int?) {
        let cost = estimateCost(
            model: model,
            input: inputTokens ?? 0,
            output: outputTokens ?? 0
        )
        let entry = UsageEntry(
            date: Date(),
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: cost
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        saveEntries()
    }

    func clearHistory() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Cost Estimation

    private func estimateCost(model: String, input: Int, output: Int) -> Double {
        // Approximate pricing per 1M tokens (as of 2025)
        let (inputRate, outputRate): (Double, Double)
        if model.contains("sonnet") {
            inputRate = 3.0
            outputRate = 15.0
        } else if model.contains("haiku") {
            inputRate = 0.25
            outputRate = 1.25
        } else {
            inputRate = 3.0
            outputRate = 15.0
        }
        return Double(input) * inputRate / 1_000_000 + Double(output) * outputRate / 1_000_000
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UsageEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
