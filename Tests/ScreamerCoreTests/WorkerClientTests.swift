import Foundation
import Testing
@testable import ScreamerCore

@Suite
struct WorkerClientTests {
    @Test func defaultConfigurationUsesLoopbackHealthURL() {
        let configuration = WorkerConfiguration()

        #expect(configuration.baseURL.absoluteString == "http://127.0.0.1:8765")
        #expect(configuration.healthURL.absoluteString == "http://127.0.0.1:8765/health")
    }

    @Test func fetchHealthDecodesWorkerPayload() async throws {
        let payload = """
        {"service":"screamer-worker","status":"ok","version":"0.1.0"}
        """

        let session = URLSession.makeMockingSession(
            statusCode: 200,
            body: Data(payload.utf8)
        )
        let client = WorkerClient(session: session)

        let health = try await client.fetchHealth()

        #expect(health.service == "screamer-worker")
        #expect(health.status == "ok")
        #expect(health.version == "0.1.0")
    }

    @Test func fetchHealthThrowsForUnexpectedStatusCode() async {
        let session = URLSession.makeMockingSession(
            statusCode: 503,
            body: Data("{}".utf8)
        )
        let client = WorkerClient(session: session)

        await #expect(throws: WorkerClientError.unexpectedStatusCode(503)) {
            try await client.fetchHealth()
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func makeMockingSession(statusCode: Int, body: Data) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.statusCode = statusCode
        MockURLProtocol.body = body
        return URLSession(configuration: configuration)
    }
}
