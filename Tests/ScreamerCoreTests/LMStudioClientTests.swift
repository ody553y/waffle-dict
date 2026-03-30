import Foundation
import Testing
@testable import ScreamerCore

@Suite(.serialized)
struct LMStudioClientTests {
    @Test func defaultConfigurationBuildsExpectedURLs() {
        let configuration = LMStudioConfiguration()

        #expect(configuration.baseURL.absoluteString == "http://127.0.0.1:1234/v1")
        #expect(configuration.modelsURL.absoluteString == "http://127.0.0.1:1234/v1/models")
        #expect(configuration.chatCompletionsURL.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
    }

    @Test func fetchModelsDecodesModelList() async throws {
        let payload = """
        {
          "data": [
            {"id": "qwen3-8b"},
            {"id": "llama-3.2-3b"}
          ]
        }
        """

        let session = URLSession.makeMockingSession(
            statusCode: 200,
            body: Data(payload.utf8)
        )
        let client = LMStudioClient(session: session)

        let models = try await client.fetchModels()

        #expect(models.map(\.id) == ["qwen3-8b", "llama-3.2-3b"])
    }

    @Test func fetchModelsThrowsNoModelsLoadedWhenResponseIsEmpty() async {
        let payload = """
        {"data":[]}
        """
        let session = URLSession.makeMockingSession(
            statusCode: 200,
            body: Data(payload.utf8)
        )
        let client = LMStudioClient(session: session)

        await #expect(throws: LMStudioClientError.noModelsLoaded) {
            try await client.fetchModels()
        }
    }

    @Test func chatCompletionPostsExpectedRequestAndDecodesResponse() async throws {
        let responsePayload = """
        {
          "id": "chatcmpl-123",
          "choices": [
            {
              "index": 0,
              "message": {"role": "assistant", "content": "Hello!"},
              "finish_reason": "stop"
            }
          ]
        }
        """

        let session = URLSession.makeMockingSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let body = try #require(requestBodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )

            #expect((payload["model"] as? String) == "qwen3-8b")
            #expect((payload["stream"] as? Bool) == false)

            let messages = try #require(payload["messages"] as? [[String: Any]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] as? String == "system")
            #expect(messages[1]["role"] as? String == "user")

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responsePayload.utf8))
        }
        let client = LMStudioClient(session: session)

        let response = try await client.chatCompletion(
            ChatCompletionRequest(
                model: "qwen3-8b",
                messages: [
                    ChatMessage(role: "system", content: "You are concise."),
                    ChatMessage(role: "user", content: "Summarise this."),
                ],
                stream: false
            )
        )

        #expect(response.id == "chatcmpl-123")
        #expect(response.choices.count == 1)
        #expect(response.choices[0].index == 0)
        #expect(response.choices[0].message.role == "assistant")
        #expect(response.choices[0].message.content == "Hello!")
        #expect(response.choices[0].finishReason == "stop")
    }

    @Test func streamChatCompletionYieldsSSEContentDeltas() async throws {
        let body = """
        data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

        data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

        data: [DONE]

        """
        let session = URLSession.makeMockingSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")

            let requestBody = try #require(requestBodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
            )
            #expect((payload["stream"] as? Bool) == true)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }
        let client = LMStudioClient(session: session)

        let stream = client.streamChatCompletion(
            ChatCompletionRequest(
                model: "qwen3-8b",
                messages: [ChatMessage(role: "user", content: "Hi")]
            )
        )
        var chunks: [String] = []
        for try await delta in stream {
            chunks.append(delta)
        }

        #expect(chunks == ["Hello", " world"])
    }

    @Test func fetchModelsMapsTransportFailuresToConnectionRefused() async {
        let transportErrors: [URLError.Code] = [
            .cannotConnectToHost,
            .networkConnectionLost,
        ]

        for code in transportErrors {
            let session = URLSession.makeMockingSession { _ in
                throw URLError(code)
            }
            let client = LMStudioClient(session: session)

            await #expect(throws: LMStudioClientError.connectionRefused) {
                try await client.fetchModels()
            }
        }

        let session = URLSession.makeMockingSession { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))
        }
        let client = LMStudioClient(session: session)

        await #expect(throws: LMStudioClientError.connectionRefused) {
            try await client.fetchModels()
        }
    }

    @Test func parseSSEDataLineThrowsOnInvalidJSON() throws {
        #expect(throws: LMStudioClientError.streamParsingFailed) {
            _ = try LMStudioSSEParser.parseDelta(from: "data: not-json")
        }
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
