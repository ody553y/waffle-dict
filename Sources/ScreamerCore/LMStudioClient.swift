import Foundation

public struct LMStudioConfiguration: Sendable, Equatable {
    public var host: String
    public var port: Int

    public init(host: String = "127.0.0.1", port: Int = 1234) {
        self.host = host
        self.port = port
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)/v1")!
    }

    public var modelsURL: URL {
        baseURL.appending(path: "models")
    }

    public var chatCompletionsURL: URL {
        baseURL.appending(path: "chat/completions")
    }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Codable, Equatable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    public var stream: Bool

    public init(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

public struct ChatCompletionResponse: Decodable, Equatable, Sendable {
    public struct Choice: Decodable, Equatable, Sendable {
        public let index: Int
        public let message: ChatMessage
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    public let id: String
    public let choices: [Choice]
}

public struct LMStudioModel: Decodable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public protocol LMStudioClientProtocol: Sendable {
    func fetchModels() async throws -> [LMStudioModel]
    func chatCompletion(_ requestPayload: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func streamChatCompletion(_ requestPayload: ChatCompletionRequest) -> AsyncThrowingStream<String, Error>
}

public enum LMStudioClientError: Error, Equatable {
    case connectionRefused
    case noModelsLoaded
    case unexpectedStatusCode(Int)
    case streamParsingFailed
}

public enum LMStudioSSEParser {
    public static func parseDelta(from line: String) throws -> String? {
        guard line.hasPrefix("data: ") else {
            return nil
        }

        let payload = String(line.dropFirst("data: ".count))

        if payload == "[DONE]" {
            return nil
        }

        guard let data = payload.data(using: .utf8) else {
            throw LMStudioClientError.streamParsingFailed
        }

        do {
            let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
            return chunk.choices.first?.delta.content
        } catch {
            throw LMStudioClientError.streamParsingFailed
        }
    }
}

public final class LMStudioClient: Sendable, LMStudioClientProtocol {
    private let configuration: LMStudioConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        configuration: LMStudioConfiguration = LMStudioConfiguration(),
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public func fetchModels() async throws -> [LMStudioModel] {
        do {
            let (data, response) = try await session.data(from: configuration.modelsURL)
            try Self.validateHTTPResponse(response, expectedStatusCode: 200)

            let decoded = try decoder.decode(ModelsResponse.self, from: data)
            guard decoded.data.isEmpty == false else {
                throw LMStudioClientError.noModelsLoaded
            }
            return decoded.data
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    public func chatCompletion(_ requestPayload: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        var payload = requestPayload
        payload.stream = false

        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            try Self.validateHTTPResponse(response, expectedStatusCode: 200)
            return try decoder.decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    public func streamChatCompletion(
        _ requestPayload: ChatCompletionRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var payload = requestPayload
                    payload.stream = true

                    var request = URLRequest(url: configuration.chatCompletionsURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try encoder.encode(payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validateHTTPResponse(response, expectedStatusCode: 200)

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        if line == "data: [DONE]" {
                            break
                        }
                        if let delta = try LMStudioSSEParser.parseDelta(from: line), delta.isEmpty == false {
                            continuation.yield(delta)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapTransportError(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private extension LMStudioClient {
    struct ModelsResponse: Decodable {
        let data: [LMStudioModel]
    }

    static func validateHTTPResponse(_ response: URLResponse, expectedStatusCode: Int) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == expectedStatusCode else {
            throw LMStudioClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    static func mapTransportError(_ error: Error) -> Error {
        if let clientError = error as? LMStudioClientError {
            return clientError
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost:
                return LMStudioClientError.connectionRefused
            default:
                break
            }
        }

        let nsError = error as NSError
        if isConnectionRefusedNSError(nsError) {
            return LMStudioClientError.connectionRefused
        }

        return error
    }

    static func isConnectionRefusedNSError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ECONNREFUSED) {
            return true
        }

        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCannotConnectToHost {
            return true
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isConnectionRefusedNSError(underlying)
        }

        return false
    }
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
