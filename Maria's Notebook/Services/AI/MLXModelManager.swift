//
//  MLXModelManager.swift
//  Maria's Notebook
//
//  Manages MLX model lifecycle: discovery, download, loading, and unloading.
//  Models are stored in Application Support/MLXModels/.
//  Guarded behind ENABLE_MLX_MODELS flag.
//

import Foundation
import OSLog

// MARK: - Model Registry (available regardless of flag)

/// Describes a downloadable MLX model from HuggingFace.
struct MLXModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let huggingFaceRepo: String
    let parameterCount: String
    let sizeGB: Double
    let description: String

    /// Curated list of recommended models for Montessori classroom use.
    static let recommended: [MLXModelInfo] = [
        MLXModelInfo(
            id: "phi-4-mini",
            name: "Phi-4 Mini",
            huggingFaceRepo: "mlx-community/Phi-4-mini-instruct-4bit",
            parameterCount: "3.8B",
            sizeGB: 2.3,
            description: "Fast, small. Good for note drafting and simple tasks."
        ),
        MLXModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            huggingFaceRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            parameterCount: "3B",
            sizeGB: 1.8,
            description: "Meta's compact model. Balanced speed and quality."
        ),
        MLXModelInfo(
            id: "mistral-7b",
            name: "Mistral 7B",
            huggingFaceRepo: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            parameterCount: "7B",
            sizeGB: 4.1,
            description: "Stronger reasoning. Needs 8GB+ RAM."
        ),
        MLXModelInfo(
            id: "gemma-2-9b",
            name: "Gemma 2 9B",
            huggingFaceRepo: "mlx-community/gemma-2-9b-it-4bit",
            parameterCount: "9B",
            sizeGB: 5.5,
            description: "Google's model. Best quality, needs 16GB+ RAM."
        ),
    ]
}

/// Status of a model in the local cache.
enum MLXModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case loaded
    case error(String)
}

#if ENABLE_MLX_MODELS && canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon

/// Manages the lifecycle of MLX models on disk and in memory.
@MainActor
@Observable
final class MLXModelManager {
    private static let logger = Logger.ai

    /// Status of each model by ID.
    var modelStatuses: [String: MLXModelStatus] = [:]

    /// The currently loaded model container, ready for inference.
    private(set) var loadedModelContainer: ModelContainer?

    /// The ID of the currently loaded model.
    private(set) var loadedModelID: String?

    /// Whether any model is currently loaded and ready for inference.
    var isReady: Bool { loadedModelContainer != nil }

    // MARK: - Directory Management

    /// Base directory for downloaded MLX models.
    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MLXModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func modelDirectory(for info: MLXModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(info.id, isDirectory: true)
    }

    // MARK: - Status

    /// Refreshes the download status for all recommended models.
    func refreshStatuses() {
        for model in MLXModelInfo.recommended {
            let dir = modelDirectory(for: model)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) {
                if loadedModelID == model.id {
                    modelStatuses[model.id] = .loaded
                } else {
                    modelStatuses[model.id] = .downloaded
                }
            } else if case .downloading = modelStatuses[model.id] {
                // Keep downloading status
            } else {
                modelStatuses[model.id] = .notDownloaded
            }
        }
    }

    // MARK: - Download

    /// Downloads a model from HuggingFace to local storage.
    func downloadModel(_ info: MLXModelInfo) async throws {
        modelStatuses[info.id] = .downloading(progress: 0)

        do {
            // MLXLLM provides model loading from HuggingFace hub
            let config = ModelConfiguration(id: info.huggingFaceRepo)
            let modelDir = modelDirectory(for: info)

            // Use MLXLMCommon's download which caches to hub directory
            // We track progress via periodic status updates
            modelStatuses[info.id] = .downloading(progress: 0.5)

            // Load the model (this downloads if needed)
            _ = try await LLMModelFactory.shared.getModelContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.modelStatuses[info.id] = .downloading(progress: progress.fractionCompleted)
                }
                return true // continue downloading
            }

            modelStatuses[info.id] = .downloaded
            Self.logger.info("Downloaded model: \(info.name)")
        } catch {
            modelStatuses[info.id] = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Load / Unload

    /// Loads a downloaded model into memory for inference.
    func loadModel(_ info: MLXModelInfo) async throws {
        // Unload any existing model first
        unloadCurrentModel()

        modelStatuses[info.id] = .loading

        do {
            let config = ModelConfiguration(id: info.huggingFaceRepo)
            let container = try await LLMModelFactory.shared.getModelContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.modelStatuses[info.id] = .loading
                }
                return true
            }

            loadedModelContainer = container
            loadedModelID = info.id
            modelStatuses[info.id] = .loaded
            Self.logger.info("Loaded model: \(info.name)")
        } catch {
            modelStatuses[info.id] = .error(error.localizedDescription)
            throw error
        }
    }

    /// Unloads the current model from memory.
    func unloadCurrentModel() {
        if let id = loadedModelID {
            modelStatuses[id] = .downloaded
        }
        loadedModelContainer = nil
        loadedModelID = nil
    }

    // MARK: - Delete

    /// Deletes a downloaded model from disk.
    func deleteModel(_ info: MLXModelInfo) throws {
        if loadedModelID == info.id {
            unloadCurrentModel()
        }

        let dir = modelDirectory(for: info)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }

        modelStatuses[info.id] = .notDownloaded
        Self.logger.info("Deleted model: \(info.name)")
    }
}

#else

// MARK: - Stub when MLX is unavailable

/// Stub manager that reports no models available.
@Observable
final class MLXModelManager: @unchecked Sendable {
    var modelStatuses: [String: MLXModelStatus] = [:]
    private(set) var loadedModelID: String?
    var isReady: Bool { false }

    func refreshStatuses() {
        for model in MLXModelInfo.recommended {
            modelStatuses[model.id] = .notDownloaded
        }
    }
}

#endif
