import SwiftUI
import UIKit
import UserNotifications
import SwimInstructorCore

/// Schreibt den Gesamtplan fort, wenn es fällig ist (alle zwei Wochen oder nach einer gemeldeten Pause), ohne den
/// Tagesplan aufzuhalten. Die Fortschreibung braucht bis zu drei Minuten; sie läuft deshalb als Hintergrundaufgabe
/// weiter, wenn die App in den Hintergrund geht, und meldet sich danach mit einer Mitteilung.
@MainActor
final class MacroReviewRunner: ObservableObject {
    private let macroLoader: MultiSportMacroLoader
    private let pauseStore: PauseReportStoring
    /// Nach einer Fortschreibung: die nächsten 14 Tage und den Tag neu abstimmen.
    var onReviewed: (@MainActor () async -> Void)?
    private var task: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(macroLoader: MultiSportMacroLoader, pauseStore: PauseReportStoring) {
        self.macroLoader = macroLoader
        self.pauseStore = pauseStore
    }

    /// Startet die Fortschreibung, wenn eine fällig ist und gerade keine läuft. Kehrt sofort zurück.
    func startIfDue(reading: AthleteStateReading) {
        guard task == nil else { return }
        let pause = pauseStore.pendingReviewReport()
        guard macroLoader.pendingReviewReason(pause: pause) != nil else { return }
        requestNotificationPermission()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Fortschreibung") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        task = Task { [weak self] in
            guard let self else { return }
            let review = await macroLoader.reviewIfDue(snapshot: reading.snapshot, workouts: reading.allWorkouts, pause: pause)
            if let review {
                if review.reason == .pause, let pause { pauseStore.markReviewed(pause.id) }
                notify(review)
                await onReviewed?()
            }
            task = nil
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ review: MacroReview) {
        let content = UNMutableNotificationContent()
        content.title = "Gesamtplan fortgeschrieben"
        content.body = review.summary.isEmpty ? review.reason.title : review.summary
        content.sound = .default
        let request = UNNotificationRequest(identifier: "macro-review-\(review.weekStart)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
