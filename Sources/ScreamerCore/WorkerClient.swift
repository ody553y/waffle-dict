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
}

public struct WorkerHealth: Decodable, Equatable, Sendable {
    public let service: String
    public let status: String
    public let version: String
}

public enum WorkerClientError: Error, Equatable {
    case unexpectedStatusCode(Int)
}

public final class WorkerClient: Sendable {
    private let session: URLSession
    private let configuration: WorkerConfiguration
    private let decoder: JSONDecoder

    public init(
        configuration: WorkerConfiguration = WorkerConfiguration(),
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
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
}
