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

    // MARK: - Private

    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
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

        // Reset state
        stopRecording()
        error = nil
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        Self.installRecognitionTap(on: inputNode, request: request, format: recordingFormat)

        let session = UUID()
        currentSession = session
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

    private struct RecognitionFailure {
        let domain: String
        let code: Int
        let details: String
    }

    private func handleRecognition(text: String?, isFinal: Bool, failure: RecognitionFailure?, session: UUID) {
        guard session == currentSession else { return }

        if let text {
            transcript = text
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

    func stopRecording() {
        currentSession = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
    }

    /// Starts or stops dictation. `typedText` is what's in the field now; the
    /// dictated words are added after it (read them from `dictatedText`).
    func toggleRecording(requiresOnDeviceRecognition: Bool = false, appendingTo typedText: String = "") {
        if isRecording {
            stopRecording()
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
