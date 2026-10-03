import Foundation

// MARK: - Practice Stats

struct PracticeStats {
    var totalSessions: Int = 0
    var totalDuration: String?
    var avgQuality: Double?
    var avgIndependence: Double?
    var topBehaviors: [String] = []
    var needsReteaching: Int = 0
    var upcomingCheckIns: Int = 0
}

struct PracticeStatsCalculator {
    static func calculate(from sessions: [CDPracticeSession]) -> PracticeStats {
        var stats = PracticeStats()
        
        stats.totalSessions = sessions.count
        stats.totalDuration = formatDuration(from: sessions)
        stats.avgQuality = calculateAverage(values: sessions.compactMap(\.practiceQualityValue))
        stats.avgIndependence = calculateAverage(values: sessions.compactMap(\.independenceLevelValue))
        stats.topBehaviors = extractTopBehaviors(from: sessions, limit: 3)
        stats.needsReteaching = sessions.filter(\.needsReteaching).count
        stats.upcomingCheckIns = sessions.filter { $0.checkInScheduledFor != nil }.count
        
        return stats
    }
    
    private static func formatDuration(from sessions: [CDPracticeSession]) -> String? {
        let totalSeconds = sessions.compactMap(\.durationInterval).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        
        let minutes = Int(totalSeconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1f hrs", hours)
        }
    }
    
    private static func calculateAverage(values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    private static func extractTopBehaviors(from sessions: [CDPracticeSession], limit: Int) -> [String] {
        var behaviorCounts: [String: Int] = [:]
        for session in sessions {
            for behavior in session.activeBehaviors {
                behaviorCounts[behavior, default: 0] += 1
            }
        }
        
        return behaviorCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}
