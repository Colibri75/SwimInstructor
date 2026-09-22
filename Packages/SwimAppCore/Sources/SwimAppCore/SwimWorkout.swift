import Foundation

public struct SwimWorkout: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let totalDistanceMeters: Double?
    public let lapCount: Int?
    public let totalStrokeCount: Double?
    public let averageHeartRate: Double?

    public init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        totalDistanceMeters: Double?,
        lapCount: Int?,
        totalStrokeCount: Double?,
        averageHeartRate: Double?
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.totalDistanceMeters = totalDistanceMeters
        self.lapCount = lapCount
        self.totalStrokeCount = totalStrokeCount
        self.averageHeartRate = averageHeartRate
    }

    public var averagePaceSecondsPer100m: Double? {
        guard let distance = totalDistanceMeters, distance > 0 else { return nil }
        return duration / (distance / 100)
    }

    /// Näherung, kein von HealthKit geliefertes offizielles SWOLF: Zeit pro Bahn plus Züge pro
    /// Bahn, gemittelt über alle Bahnen. Ein echter SWOLF-Wert existiert nur für Workouts, die
    /// Apples eigene Schwimm-App mit Lap-Metadaten aufgezeichnet hat.
    public var approximateAverageSwolf: Double? {
        guard let laps = lapCount, laps > 0, let strokes = totalStrokeCount else { return nil }
        return (duration / Double(laps)) + (strokes / Double(laps))
    }
}
