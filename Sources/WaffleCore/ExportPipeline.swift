import Foundation

public struct ExportPipelineStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var templateID: UUID
    public var templateName: String
    public var templatePrompt: String

    public init(
        id: UUID = UUID(),
        templateID: UUID,
        templateName: String,
        templatePrompt: String
    ) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.templatePrompt = templatePrompt
    }
}

public enum ExportPipelineOutputDestination: String, Codable, CaseIterable, Sendable {
    case clipboard
    case none
}

public struct ExportPipeline: Codable, Equatable, Identifiable, Sendable {
    public static let maxStepCount = 10

    public var id: UUID
    public var name: String
    public var steps: [ExportPipelineStep]
    public var runAutomatically: Bool
    public var outputDestination: ExportPipelineOutputDestination
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [ExportPipelineStep],
        runAutomatically: Bool,
        outputDestination: ExportPipelineOutputDestination,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.runAutomatically = runAutomatically
        self.outputDestination = outputDestination
        self.createdAt = createdAt
    }
}

public final class ExportPipelineStore: @unchecked Sendable {
    public static let storageKey = "exportPipelines"
    public static let maxPipelineCount = 10

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    public func load() -> [ExportPipeline] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return []
        }

        do {
            return try decoder.decode([ExportPipeline].self, from: data)
        } catch {
            return []
        }
    }

    public func save(_ pipelines: [ExportPipeline]) {
        guard let data = try? encoder.encode(pipelines) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    public func add(_ pipeline: ExportPipeline) {
        var pipelines = load()
        guard pipelines.count < Self.maxPipelineCount else { return }
        pipelines.append(pipeline)
        save(pipelines)
    }

    public func update(_ pipeline: ExportPipeline) {
        var pipelines = load()
        guard let index = pipelines.firstIndex(where: { $0.id == pipeline.id }) else { return }
        pipelines[index] = pipeline
        save(pipelines)
    }

    public func delete(id: UUID) {
        var pipelines = load()
        pipelines.removeAll { $0.id == id }
        save(pipelines)
    }
}
