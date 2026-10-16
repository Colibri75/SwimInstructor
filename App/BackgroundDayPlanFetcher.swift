import Foundation
import SwimInstructorCore

/// Holt den Tagesplan über eine Übertragung im Hintergrund: iOS führt die Anfrage zu Ende, auch wenn die App wieder
/// schläft oder beendet wurde, und weckt sie mit der Antwort. Dein Coach braucht für einen Tagesplan meist länger als die
/// halbe Minute, die iOS der App im Hintergrund gibt.
///
/// Jede Antwort geht an `onDelivery`, ob die App die Anfrage noch im Speicher hat oder nicht: Die Vorgabe, zu der die
/// Anfrage gehört, reist in der Aufgabe selbst mit.
final class BackgroundDayPlanFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let sessionID = "com.kellner.SwimInstructor.dayplan"
    static let shared = BackgroundDayPlanFetcher()
    /// Wer bis dahin nicht durchkommt, kommt zu spät: Dann plant Heute beim Öffnen selbst.
    static let giveUpAfter: TimeInterval = 3 * 3_600

    /// Bekommt jede Antwort auf dem Main Actor: den Plan (`nil` bei einem Fehler) und die Vorgabe der Anfrage.
    var onDelivery: (@MainActor (DayPlanV2Response?, DayTargetV2) -> Void)?

    private struct Context: Codable {
        let target: DayTargetV2
        /// Name der Datei mit dem Body im Cache-Ordner.
        let file: String
    }

    private var session: URLSession!
    /// Nur auf der seriellen Queue der Sitzung.
    private var received: [Int: Data] = [:]
    private let lock = NSLock()
    private var eventsWaiter: CheckedContinuation<Void, Never>?
    private var eventsFinished = false

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = PlanAPIClient.planTimeout
        configuration.timeoutIntervalForResource = Self.giveUpAfter
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Läuft schon eine Anfrage?
    func hasPendingRequest() async -> Bool {
        await session.allTasks.contains { $0.state == .running || $0.state == .suspended }
    }

    /// Gibt die Anfrage an iOS ab. Hintergrund-Übertragungen brauchen den Body als Datei.
    func start(_ request: URLRequest, target: DayTargetV2) throws {
        let file = "dayplan-\(UUID().uuidString).json"
        try (request.httpBody ?? Data()).write(to: Self.directory.appendingPathComponent(file))
        var upload = request
        upload.httpBody = nil
        let task = session.uploadTask(with: upload, fromFile: Self.directory.appendingPathComponent(file))
        task.taskDescription = String(decoding: try JSONEncoder().encode(Context(target: target, file: file)), as: UTF8.self)
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

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let data = received.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard let description = task.taskDescription,
              let context = try? JSONDecoder().decode(Context.self, from: Data(description.utf8)) else { return }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(context.file))
        var plan: DayPlanV2Response?
        if error == nil, let status = (task.response as? HTTPURLResponse)?.statusCode {
            plan = try? PlanAPIClient.decodeDayPlanV2(data: data, statusCode: status)
        }
        // Über die Main-Queue, damit die Zustellung vor dem Ende der Ereignisse (unten) läuft.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onDelivery?(plan, context.target)
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
