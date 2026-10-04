import AVFoundation

/// Liest die Ansagen zu den Schritten vor ("Intervall, 2 von 6. 3 min zügig."), über den Lautsprecher der Uhr oder
/// verbundene Kopfhörer. Haptik gibt es immer, die Ansagen lassen sich vor dem Start abschalten.
@MainActor
final class Announcer {
    var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
