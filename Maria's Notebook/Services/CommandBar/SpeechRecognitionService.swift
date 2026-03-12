// SpeechRecognitionService.swift
// Speech-to-text service wrapping SFSpeechRecognizer for the command bar

import Foundation
import OSLog
import Speech
import AVFoundation

@Observable
@MainActor
final class SpeechRecognitionService {
    private static let logger = Logger.app_

    // MARK: - Public State

    var isRecording = false
    var transcript = ""
    var error: String?
    var permissionGranted = false

    // MARK: - Private

    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "Speech recognition permission denied."
            return false
        }

        #if os(iOS)
        let audioStatus: Bool
        if #available(iOS 17.0, *) {
            audioStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            audioStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard audioStatus else {
            error = "Microphone permission denied."
            return false
        }
        #endif

        permissionGranted = true
        return true
    }

    // MARK: - Recording

    func startRecording() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition is not available."
            return
        }

        // Reset state
        stopRecording()
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    // Don't report cancellation as an error
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        Self.logger.warning("Speech recognition error: \(error)")
                        self.error = error.localizedDescription
                    }
                    self.stopRecording()
                }

                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            Self.logger.info("Started speech recording")
        } catch {
            Self.logger.warning("Failed to start audio engine: \(error)")
            self.error = "Failed to start recording."
            stopRecording()
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                if !permissionGranted {
                    let granted = await requestPermission()
                    guard granted else { return }
                }
                startRecording()
            }
        }
    }
}
