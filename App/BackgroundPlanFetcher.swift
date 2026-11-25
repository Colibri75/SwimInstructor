import Foundation
import SwimInstructorCore

/// Holt Pläne über eine Übertragung im Hintergrund: iOS führt die Anfrage zu Ende, auch wenn die App wieder schläft oder
/// beendet wurde, und weckt sie mit der Antwort. Dein Coach braucht für den Tagesplan meist länger als die halbe Minute,
/// die iOS der App im Hintergrund gibt, für die nächsten 14 Tage bis zu zwei Minuten.
///
/// Jede Antwort geht an `onDayDelivery` oder `onWeekDelivery`, ob die App die Anfrage noch im Speicher hat oder nicht:
/// Was nach der Antwort gilt (Vorgabe, Zeitraum), reist in der Aufgabe selbst mit.
final class BackgroundPlanFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Bleibt beim alten Namen: Laufende Übertragungen gehören zu dieser Kennung.
    static let sessionID = "com.kellner.SwimInstructor.dayplan"
    static let shared = BackgroundPlanFetcher()
    /// Wer bis dahin nicht durchkommt, kommt zu spät: Dann plant Aktuell beim Öffnen selbst.
    static let giveUpAfter: TimeInterval = 3 * 3_600

    /// Bekommt jede Antwort auf den Tagesplan auf dem Main Actor: den Plan (`nil` bei einem Fehler) und die Vorgabe.
    var onDayDelivery: (@MainActor (DayPlanV2Response?, DayTargetV2) -> Void)?
    /// Bekommt jede Antwort auf die 14 Tage auf dem Main Actor: den Plan (`nil` bei einem Fehler) und was danach gilt.
    var onWeekDelivery: (@MainActor (WeekPlanV2Response?, BackgroundReplan) -> Void)?

    private enum Kind: String, Codable {
        case day, week
    }

    private struct Context: Codable {
        /// Fehlt bei Aufgaben von vor den 14 Tagen im Hintergrund: Tagesplan.
        let kind: Kind?
        let target: DayTargetV2?
        let replan: BackgroundReplan?
        /// Wann die Anfrage abgegeben wurde.
        let startedAt: Date?
        /// Name der Datei mit dem Body im Cache-Ordner.
        let file: String
    }

    private var session: URLSession!
    /// Nur auf der seriellen Queue der Sitzung.
    private var received: [Int: Data] = [:]
    private let lock = NSLock()
    private var eventsWaiter: CheckedContinuation<Void, Never>?
    private var eventsFinished = false
    /// Wer auf die Antwort der 14 Tage wartet (nur auf dem Main Actor).
    private var weekWaiters: [CheckedContinuation<Void, Never>] = []
    /// Zählt die zugestellten Antworten der 14 Tage (nur auf dem Main Actor).
    private var weekDeliveries = 0

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // Die 14 Tage brauchen das lange Zeitlimit; es gilt, solange keine Daten kommen.
        configuration.timeoutIntervalForRequest = PlanAPIClient.macroTimeout
        configuration.timeoutIntervalForResource = Self.giveUpAfter
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Läuft schon eine Anfrage?
    func hasPendingRequest() async -> Bool {
        await session.allTasks.contains { $0.state == .running || $0.state == .suspended }
    }

    /// Wann die laufende Abstimmung der 14 Tage abgegeben wurde, `nil` ohne eine.
    func pendingWeekStart() async -> Date? {
        await session.allTasks
            .filter { $0.state == .running || $0.state == .suspended }
            .compactMap { Self.context(of: $0) }
            .filter { $0.kind == .week }
            .map { $0.startedAt ?? .distantPast }
            .max()
    }

    /// Beim Öffnen: Ist die Abstimmung der 14 Tage gerade im Hintergrund unterwegs, auf ihre Antwort warten statt
    /// dieselbe Anfrage noch einmal zu stellen, höchstens so lange, wie dein Coach dafür braucht. Hängt eine ältere (etwa
    /// ohne Netz), plant das Öffnen selbst; ihre Antwort kommt dann zu spät und wird verworfen.
    @MainActor
    func waitForPendingWeek(within limit: TimeInterval = PlanAPIClient.macroTimeout) async {
        let deliveries = weekDeliveries
        guard let started = await pendingWeekStart(), weekDeliveries == deliveries else { return }
        let remaining = started.addingTimeInterval(limit).timeIntervalSinceNow
        guard remaining > 0 else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            weekWaiters.append(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                MainActor.assumeIsolated { self?.resumeWeekWaiters() }
            }
        }
    }

    @MainActor
    private func resumeWeekWaiters() {
        let waiters = weekWaiters
        weekWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// Gibt die Anfrage für den Tagesplan an iOS ab.
    func start(_ request: URLRequest, target: DayTargetV2) throws {
        try start(request, prefix: "dayplan", context: { Context(kind: .day, target: target, replan: nil, startedAt: Date(), file: $0) })
    }

    /// Gibt die Anfrage für die nächsten 14 Tage an iOS ab.
    func start(_ request: URLRequest, replan: BackgroundReplan) throws {
        try start(request, prefix: "weekplan", context: { Context(kind: .week, target: nil, replan: replan, startedAt: Date(), file: $0) })
    }

    /// Hintergrund-Übertragungen brauchen den Body als Datei.
    private func start(_ request: URLRequest, prefix: String, context: (String) -> Context) throws {
        let file = "\(prefix)-\(UUID().uuidString).json"
        try (request.httpBody ?? Data()).write(to: Self.directory.appendingPathComponent(file))
        var upload = request
        upload.httpBody = nil
        let task = session.uploadTask(with: upload, fromFile: Self.directory.appendingPathComponent(file))
        task.taskDescription = String(decoding: try JSONEncoder().encode(context(file)), as: UTF8.self)
        task.resume()
    }

    /// Für `.backgroundTask(.urlSession)`: iOS weckt die App, weil Antworten da sind. Wartet, bis alle zugestellt sind.
    func handleEvents() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if eventsFinished {
                eventsFinished = false
                lock.unlock()
                continuation.resume()
                return
            }
            eventsWaiter = continuation
            lock.unlock()
        }
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private static func context(of task: URLSessionTask) -> Context? {
        guard let description = task.taskDescription else { return nil }
        return try? JSONDecoder().decode(Context.self, from: Data(description.utf8))
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let data = received.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard let context = Self.context(of: task) else { return }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(context.file))
        let status = error == nil ? (task.response as? HTTPURLResponse)?.statusCode : nil
        // Über die Main-Queue, damit die Zustellung vor dem Ende der Ereignisse (unten) läuft.
        switch context.kind ?? .day {
        case .day:
            guard let target = context.target else { return }
            let plan = status.flatMap { try? PlanAPIClient.decodeDayPlanV2(data: data, statusCode: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.onDayDelivery?(plan, target)
                }
            }
        case .week:
            guard let replan = context.replan else { return }
            let plan = status.flatMap { try? PlanAPIClient.decodeWeekPlanV2(data: data, statusCode: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.weekDeliveries += 1
                    self.onWeekDelivery?(plan, replan)
                    // Erst nach dem Übernehmen: Wer beim Öffnen wartet, findet die Tage schon abgestimmt.
                    self.resumeWeekWaiters()
                }
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.lock.lock()
            let waiter = self.eventsWaiter
            self.eventsWaiter = nil
            if waiter == nil { self.eventsFinished = true }
            self.lock.unlock()
            waiter?.resume()
        }
    }
}
