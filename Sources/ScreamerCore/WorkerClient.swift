import Foundation

public struct WorkerConfiguration: Sendable, Equatable {
    public var host: String
    public var port: Int

    public init(host: String = "127.0.0.1", port: Int = 8765) {
        self.host = host
        self.port = port
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public var healthURL: URL {
        baseURL.appending(path: "health")
    }

    public var fileTranscriptionsURL: URL {
        baseURL.appending(path: "transcriptions/file")
    }
}

public struct WorkerHealth: Decodable, Equatable, Sendable {
    public let service: String
    public let status: String
    public let version: String
    public let modelLoaded: Bool
    public let modelID: String?

    enum CodingKeys: String, CodingKey {
        case service
        case status
        case version
        case modelLoaded = "model_loaded"
        case modelID = "model_id"
    }
}

public struct FileTranscriptionRequestPayload: Encodable, Equatable, Sendable {
    public let jobID: String
    public let modelID: String
    public let filePath: String
    public let languageHint: String?
    public let translateToEnglish: Bool

    public init(
        jobID: String,
        modelID: String,
        filePath: String,
        languageHint: String?,
        translateToEnglish: Bool
    ) {
        self.jobID = jobID
        self.modelID = modelID
        self.filePath = filePath
        self.languageHint = languageHint
        self.translateToEnglish = translateToEnglish
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case modelID = "model_id"
        case filePath = "file_path"
        case languageHint = "language_hint"
        case translateToEnglish = "translate_to_english"
    }
}

public struct FileTranscriptionResponsePayload: Decodable, Equatable, Sendable {
    public struct Segment: Decodable, Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String

        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public let jobID: String
    public let backendID: String
    public let text: String
    public let segments: [Segment]?

    public init(
        jobID: String,
        backendID: String,
        text: String,
        segments: [Segment]? = nil
    ) {
        self.jobID = jobID
        self.backendID = backendID
        self.text = text
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case backendID = "backend_id"
        case text
        case segments
    }
}

public enum WorkerClientError: Error, Equatable {
    case unexpectedStatusCode(Int)
}

public final class WorkerClient: Sendable {
    private let session: URLSession
    private let configuration: WorkerConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        configuration: WorkerConfiguration = WorkerConfiguration(),
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public func fetchHealth() async throws -> WorkerHealth {
        let (data, response) = try await session.data(from: configuration.healthURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkerClientError.unexpectedStatusCode(httpResponse.statusCode)
        }

        return try decoder.decode(WorkerHealth.self, from: data)
    }

    public func transcribeFile(
        _ requestPayload: FileTranscriptionRequestPayload
    ) async throws -> FileTranscriptionResponsePayload {
        var request = URLRequest(url: configuration.fileTranscriptionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestPayload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkerClientError.unexpectedStatusCode(httpResponse.statusCode)
        }

        return try decoder.decode(FileTranscriptionResponsePayload.self, from: data)
    }
}
