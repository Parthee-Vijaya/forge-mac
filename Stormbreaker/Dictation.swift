import Foundation
import Speech
import AVFoundation

/// B15: push-to-talk dictation via Apple's on-device Speech framework (Danish
/// locale, falling back to the system default). Live partial transcripts are
/// streamed back through `onPartial`. Defensive throughout: a missing mic, denied
/// permission, or unavailable recognizer surfaces via `onError` rather than
/// crashing. macOS routes mic input through AVAudioEngine directly (no audio
/// session). Requires NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription.
@MainActor
final class Dictation {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "da-DK"))
        ?? SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// Begin capturing. `onPartial` fires with the running transcript; `onError`
    /// fires once on any failure (and leaves dictation stopped).
    func start(onPartial: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard !isRunning else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    onError("Talegenkendelse er ikke tilladt — slå det til i Systemindstillinger.")
                    return
                }
                guard let recognizer = self.recognizer, recognizer.isAvailable else {
                    onError("Talegenkendelse er ikke tilgængelig på denne Mac.")
                    return
                }
                do {
                    try self.beginCapture(recognizer: recognizer, onPartial: onPartial, onError: onError)
                } catch {
                    self.cleanup()
                    onError("Kunne ikke starte mikrofonen: \(error.localizedDescription)")
                }
            }
        }
    }

    private func beginCapture(recognizer: SFSpeechRecognizer,
                              onPartial: @escaping (String) -> Void,
                              onError: @escaping (String) -> Void) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result { onPartial(result.bestTranscription.formattedString) }
                if let error, self?.isRunning == true {
                    self?.cleanup()
                    onError("Talegenkendelse stoppede: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stop capturing (the partial transcript already streamed stays in the field).
    func stop() { cleanup() }

    private func cleanup() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
    }
}
