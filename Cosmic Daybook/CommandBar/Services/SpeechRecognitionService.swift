// SpeechRecognitionService.swift
// Speech-to-text service wrapping SFSpeechRecognizer for the command bar

import Foundation
import OSLog
import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService {
    private static let logger = Logger.app_

    // MARK: - Public State

    var isRecording = false
    /// Stopped listening, waiting for Speech's last words (`finishRecording`):
    /// the couple of seconds after a stop when `isRecording` is already false
    /// but the transcript may still change.
    private(set) var isFinishing = false
    /// What this dictation has heard so far. Cleared when recording starts, so
    /// it only ever holds the current dictation's words.
    var transcript = ""
    var error: String?
    var permissionGranted = false

    /// What was already in the field when dictation started. Dictated words go
    /// after it rather than replacing it.
    private(set) var typedBeforeDictation = ""

    /// The field's text while dictating: what she typed, then what she said.
    var dictatedText: String {
        Self.appending(transcript, to: typedBeforeDictation)
    }

    /// Called with `dictatedText` each time the current dictation hears more,
    /// while it is recording or finishing. Called at once, not on the next
    /// redraw, so the last words are in before a waiting `finishRecording`
    /// returns (an `onChange` of `transcript` ran after it, with the
    /// dictation already over).
    @ObservationIgnored var onDictatedText: ((String) -> Void)?

    // MARK: - Private

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var audioEngine: AVAudioEngine?
    /// Everyone waiting for the last words after the microphone stopped
    /// (`finishRecording`): the mic button's stop and a Send can both wait.
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishTimeout: Task<Void, Never>?
    /// How long a stop waits for Speech's final words before giving up on them.
    private static let finishGrace: Duration = .seconds(2)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    /// Identifies the dictation in progress, so a late callback from one that
    /// was already stopped can't change the text or stop the next one.
    private var currentSession: UUID?

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        // `@Sendable`: Speech calls this on a queue of its own. A plain closure
        // here would be main-actor isolated and halt the app when called off
        // the main thread.
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "Cosmic Daybook isn't allowed to use dictation. "
                + "Turn it on in \(SystemSettingsApp.privacyPath("Speech Recognition"))."
            return false
        }

        #if os(iOS)
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Cosmic Daybook can't use the microphone. "
                + "Turn it on in \(SystemSettingsApp.privacyPath("Microphone"))."
            return false
        }
        #endif

        permissionGranted = true
        return true
    }

    // MARK: - Recording

    func startRecording(requiresOnDeviceRecognition: Bool = false) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Dictation isn't available right now. Type instead."
            return
        }
        guard !requiresOnDeviceRecognition || speechRecognizer.supportsOnDeviceRecognition else {
            error = "Dictation that stays on this device isn't available here. Type the observation instead."
            return
        }

        let session = beginSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        recognitionRequest = request

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        Self.installRecognitionTap(on: inputNode, request: request, format: recordingFormat)

        // `@Sendable`, so it carries no main-actor check: the handler can run
        // on the recognizer's queue. Only plain values cross to the main actor.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { error in
                let nsError = error as NSError
                return RecognitionFailure(
                    domain: nsError.domain, code: nsError.code, details: String(describing: error)
                )
            }
            Task { @MainActor [weak self] in
                self?.handleRecognition(text: text, isFinal: isFinal, failure: failure, session: session)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            Self.logger.info("Started speech recording")
        } catch {
            Self.logger.warning("Failed to start audio engine: \(error)")
            self.error = "Couldn't start dictation. Try again, or type instead."
            stopRecording()
        }
    }

    /// A new dictation's bookkeeping: any earlier one torn down, the
    /// transcript cleared, and the session its callbacks must carry.
    private func beginSession() -> UUID {
        stopRecording()
        error = nil
        transcript = ""
        let session = UUID()
        currentSession = session
        return session
    }

    private struct RecognitionFailure {
        let domain: String
        let code: Int
        let details: String
    }

    private func handleRecognition(text: String?, isFinal: Bool, failure: RecognitionFailure?, session: UUID) {
        guard session == currentSession else { return }

        if let text {
            transcript = text
            if !text.isEmpty { onDictatedText?(dictatedText) }
        }

        if let failure {
            if !Self.isNormalStop(domain: failure.domain, code: failure.code) {
                Self.logger.warning("Speech recognition error: \(failure.details)")
                error = "Dictation stopped. Try again, or type instead."
            }
            stopRecording()
        } else if isFinal {
            stopRecording()
        }
    }

    /// Errors Speech reports when dictation ends normally: the guide stopped it
    /// (the request is canceled) or she said nothing. Neither is worth a message.
    nonisolated static func isNormalStop(domain: String, code: Int) -> Bool {
        switch (domain, code) {
        case ("kLSRErrorDomain", 301),         // Request was canceled
             ("kAFAssistantErrorDomain", 216), // Canceled
             ("kAFAssistantErrorDomain", 1110): // No speech detected
            true
        default:
            false
        }
    }

    /// Dictated words go after what was typed, with one space between.
    nonisolated static func appending(_ dictated: String, to typed: String) -> String {
        let dictated = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dictated.isEmpty else { return typed }
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return dictated }
        return typed.last?.isWhitespace == true ? typed + dictated : typed + " " + dictated
    }

    /// Installs the audio tap using the pre-iOS-27 API. The Swift-refined replacement
    /// (`installAudioTap`) delivers `AVReadOnlyAudioPCMBuffer`, which
    /// `SFSpeechAudioBufferRecognitionRequest.append` cannot accept as of Xcode 27 beta 1.
    /// Re-evaluate on each beta seed and migrate once Speech consumes read-only buffers.
    ///
    /// `nonisolated` so the tap block built here carries no main-actor check:
    /// the audio engine calls it on its own real-time thread.
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Speech cannot consume the iOS 27 replacement tap API yet")
    nonisolated private static func installRecognitionTap(
        on inputNode: AVAudioInputNode,
        request: SFSpeechAudioBufferRecognitionRequest,
        format: AVAudioFormat
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    /// Tears dictation down at once, dropping words not yet transcribed: for
    /// a sheet closing, or a new dictation starting. A stop the guide asks for
    /// goes through `finishRecording` instead.
    func stopRecording() {
        currentSession = nil

        stopListening()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        isFinishing = false

        finishTimeout?.cancel()
        finishTimeout = nil
        let waiters = finishWaiters
        finishWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Stops listening but lets Speech finish the words it has already
    /// heard. `endAudio()` finishes processing the audio already accepted,
    /// where `cancel()` dropped the last words (bug hunt 2026-10-11 #53).
    /// Returns once the final transcript is in, or after `finishGrace` if
    /// Speech never sends one. Called again while finishing, it waits for
    /// the same finish: a Send in those seconds used to return at once and
    /// organize the words heard so far (review (b) 2026-10-11).
    func finishRecording() async {
        if !isFinishing {
            guard isRecording, let session = currentSession else { return }
            stopListening()
            recognitionRequest?.endAudio()
            isRecording = false
            isFinishing = true
            finishTimeout = Task { [weak self] in
                try? await Task.sleep(for: Self.finishGrace)
                guard let self, self.currentSession == session else { return }
                self.stopRecording()
            }
        }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    private func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    #if DEBUG
    /// Puts the service where `startRecording` leaves it once the microphone
    /// runs, without one, so tests can feed it recognition results.
    func simulateRecording(appendingTo typedText: String) -> UUID {
        typedBeforeDictation = typedText
        let session = beginSession()
        isRecording = true
        return session
    }

    /// A recognition result for `session`, as Speech's callback delivers it.
    func simulateResult(_ text: String, isFinal: Bool, session: UUID) {
        handleRecognition(text: text, isFinal: isFinal, failure: nil, session: session)
    }
    #endif

    /// Starts or stops dictation. `typedText` is what's in the field now; the
    /// dictated words are added after it (read them from `dictatedText`).
    /// Stopping keeps the last words: they arrive in `transcript` a moment later.
    func toggleRecording(requiresOnDeviceRecognition: Bool = false, appendingTo typedText: String = "") {
        if isRecording {
            Task { await finishRecording() }
        } else {
            Task {
                if !permissionGranted {
                    let granted = await requestPermission()
                    guard granted else { return }
                }
                typedBeforeDictation = typedText
                startRecording(requiresOnDeviceRecognition: requiresOnDeviceRecognition)
            }
        }
    }
}
