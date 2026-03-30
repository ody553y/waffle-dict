import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct WebhookServiceTests {
    @Test func signatureHexMatchesKnownInput() {
        let body = Data("hello".utf8)
        let signature = WebhookService.signatureHex(secret: "secret", body: body)

        #expect(signature == "88aab3ede8d3adf94d26ab90d3bafd4a2083070c3bcce9c014ee04a443847c0b")
    }

    @Test func deliverRetriesOnServerErrors() async {
        nonisolated(unsafe) var attemptCount = 0
        let session = URLSession.makeWebhookMockingSession { request in
            attemptCount += 1
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://hooks.example.com/ingest")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)
        nonisolated(unsafe) var sleepCalls: [UInt64] = []
        let service = WebhookService(
            session: session,
            deliveryLog: log,
            appVersion: "test",
            sleep: { sleepCalls.append($0) }
        )

        await service.deliver(transcript: sampleTranscript(), config: sampleConfig())

        #expect(attemptCount == 4)
        #expect(sleepCalls == [2_000_000_000, 4_000_000_000, 8_000_000_000])
    }

    @Test func deliverDoesNotRetryOnClientErrors() async {
        nonisolated(unsafe) var attemptCount = 0
        let session = URLSession.makeWebhookMockingSession { request in
            attemptCount += 1
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://hooks.example.com/ingest")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)
        let service = WebhookService(
            session: session,
            deliveryLog: log,
            appVersion: "test",
            sleep: { _ in }
        )

        await service.deliver(transcript: sampleTranscript(), config: sampleConfig())

        #expect(attemptCount == 1)
    }

    @Test func sendTestPayloadReturnsHTTPStatusCode() async throws {
        let session = URLSession.makeWebhookMockingSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://hooks.example.com/ingest")!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let service = WebhookService(
            session: session,
            appVersion: "test",
            sleep: { _ in }
        )

        let statusCode = try await service.sendTestPayload(config: sampleConfig())

        #expect(statusCode == 204)
    }

    @Test func deliverAppendsSucceededLogEntry() async {
        let session = URLSession.makeWebhookMockingSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://hooks.example.com/ingest")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)
        let service = WebhookService(
            session: session,
            deliveryLog: log,
            appVersion: "test",
            sleep: { _ in }
        )

        await service.deliver(transcript: sampleTranscript(), config: sampleConfig())

        let entries = log.load()
        #expect(entries.count == 1)
        #expect(entries[0].event == "transcript.created")
        #expect(entries[0].statusCode == 200)
        #expect(entries[0].succeeded)
        #expect(entries[0].errorMessage == nil)
    }

    @Test func deliverAppendsFailedLogEntryOnNetworkError() async {
        let session = URLSession.makeWebhookMockingSession { _ in
            throw URLError(.timedOut)
        }
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)
        let service = WebhookService(
            session: session,
            deliveryLog: log,
            appVersion: "test",
            sleep: { _ in }
        )

        await service.deliver(transcript: sampleTranscript(), config: sampleConfig())

        let entries = log.load()
        #expect(entries.count == 1)
        #expect(entries[0].event == "transcript.created")
        #expect(entries[0].statusCode == nil)
        #expect(entries[0].succeeded == false)
        #expect(entries[0].errorMessage?.isEmpty == false)
    }

    private func sampleConfig() -> WebhookConfiguration {
        WebhookConfiguration(
            isEnabled: true,
            endpointURL: "https://hooks.example.com/ingest",
            hmacSecret: "abc123",
            includeSpeakerMap: true,
            includeSegments: true
        )
    }

    private func sampleTranscript() -> TranscriptRecord {
        TranscriptRecord(
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: 12.3,
            text: "hello webhook",
            segments: [TranscriptSegment(start: 0, end: 1, text: "hello", speaker: "SPEAKER_00")],
            speakerMap: ["SPEAKER_00": "Alice"]
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WebhookServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class WebhookMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, body) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func makeWebhookMockingSession(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebhookMockURLProtocol.self]
        WebhookMockURLProtocol.requestHandler = requestHandler
        return URLSession(configuration: configuration)
    }
}
