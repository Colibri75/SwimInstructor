import AVFoundation
import SwimInstructorCore

/// Liest die Ansagen zu den Schritten vor ("Intervall, 2 von 6. 3 min zügig."), über den Lautsprecher der Uhr oder
/// verbundene Kopfhörer. Haptik gibt es immer, die Ansagen lassen sich vor dem Start abschalten.
@MainActor
final class Announcer {
    var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        synthesizer.speak(utterance)
    }

    /// Stimme in der Sprache der App; gibt es dafür keine, nimmt die Uhr ihre Standardstimme.
    private static var voiceLanguage: String {
        switch AppLocale.languageCode {
        case "zh-Hans": return "zh-CN"
        case "hi": return "hi-IN"
        case "de": return "de-DE"
        case let code: return code
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
