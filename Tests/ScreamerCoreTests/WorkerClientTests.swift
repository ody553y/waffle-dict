import Foundation
import Testing
@testable import ScreamerCore

@Suite(.serialized)
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

    @Test func transcribeFilePostsExpectedRequestAndDecodesResponse() async throws {
        let responsePayload = """
        {"job_id":"job-123","backend_id":"stub-whisper","text":"transcribed:demo.wav:stub-whisper"}
        """

        let session = URLSession.makeMockingSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://127.0.0.1:8765/transcriptions/file")

            let body = try #require(requestBodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )

            #expect((payload["job_id"] as? String) == "job-123")
            #expect((payload["model_id"] as? String) == "stub-whisper")
            #expect((payload["file_path"] as? String) == "/tmp/demo.wav")
            #expect((payload["language_hint"] as? String) == "en")
            #expect((payload["translate_to_english"] as? Bool) == false)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responsePayload.utf8))
        }
        let client = WorkerClient(session: session)

        let response = try await client.transcribeFile(
            FileTranscriptionRequestPayload(
                jobID: "job-123",
                modelID: "stub-whisper",
                filePath: "/tmp/demo.wav",
                languageHint: "en",
                translateToEnglish: false
            )
        )

        #expect(response.jobID == "job-123")
        #expect(response.backendID == "stub-whisper")
        #expect(response.text == "transcribed:demo.wav:stub-whisper")
    }
}

private func requestBodyData(for request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        guard bytesRead > 0 else { break }
        data.append(buffer, count: bytesRead)
    }

    return data
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let requestHandler = Self.requestHandler {
            do {
                let (response, body) = try requestHandler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
            return
        }

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
        MockURLProtocol.requestHandler = nil
        return URLSession(configuration: configuration)
    }

    static func makeMockingSession(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = requestHandler
        return URLSession(configuration: configuration)
    }
}
