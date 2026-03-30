import CryptoKit
import Foundation

public struct WebhookPayload: Codable, Equatable, Sendable {
    public let event: String
    public let transcriptID: Int64?
    public let createdAt: Date
    public let sourceType: String
    public let modelID: String
    public let durationSeconds: Double?
    public let text: String
    public let speakerMap: [String: String]?
    public let segments: [WebhookSegment]?

    public init(
        event: String,
        transcriptID: Int64?,
        createdAt: Date,
        sourceType: String,
        modelID: String,
        durationSeconds: Double?,
        text: String,
        speakerMap: [String: String]?,
        segments: [WebhookSegment]?
    ) {
        self.event = event
        self.transcriptID = transcriptID
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.modelID = modelID
        self.durationSeconds = durationSeconds
        self.text = text
        self.speakerMap = speakerMap
        self.segments = segments
    }
}

public struct WebhookSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let speaker: String?

    public init(start: Double, end: Double, text: String, speaker: String?) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public enum WebhookServiceError: Error, Equatable {
    case invalidEndpointURL
    case invalidResponse
    case unexpectedStatusCode(Int)
}

public final class WebhookService: @unchecked Sendable {
    public typealias SleepHandler = @Sendable (UInt64) async -> Void

    private static let retryDelaysNanoseconds: [UInt64] = [
        2_000_000_000,
        4_000_000_000,
        8_000_000_000,
    ]

    private let session: URLSession
    private let encoder: JSONEncoder
    private let deliveryLog: WebhookDeliveryLog
    private let appVersion: String
    private let sleep: SleepHandler

    public init(
        session: URLSession = .shared,
        encoder: JSONEncoder? = nil,
        deliveryLog: WebhookDeliveryLog = WebhookDeliveryLog(),
        appVersion: String? = nil,
        sleep: @escaping SleepHandler = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.session = session
        let resolvedEncoder = encoder ?? JSONEncoder()
        resolvedEncoder.dateEncodingStrategy = .iso8601
        self.encoder = resolvedEncoder
        self.deliveryLog = deliveryLog
        self.appVersion = appVersion ?? Self.defaultAppVersion()
        self.sleep = sleep
    }

    public func deliver(transcript: TranscriptRecord, config: WebhookConfiguration) async {
        guard config.isDeliveryEnabled else { return }

        let payload = makeTranscriptPayload(from: transcript, config: config)

        do {
            let statusCode = try await sendDeliveryPayload(payload, event: "transcript.created", config: config)
            deliveryLog.append(
                WebhookDeliveryEntry(
                    deliveredAt: Date(),
                    event: "transcript.created",
                    statusCode: statusCode,
                    succeeded: true,
                    errorMessage: nil
                )
            )
        } catch {
            deliveryLog.append(
                WebhookDeliveryEntry(
                    deliveredAt: Date(),
                    event: "transcript.created",
                    statusCode: statusCode(from: error),
                    succeeded: false,
                    errorMessage: Self.truncatedErrorMessage(error)
                )
            )
        }
    }

    public func sendTestPayload(config: WebhookConfiguration) async throws -> Int {
        let payload = WebhookPayload(
            event: "test",
            transcriptID: nil,
            createdAt: Date(),
            sourceType: "test",
            modelID: "test",
            durationSeconds: nil,
            text: "This is a test payload from Waffle.",
            speakerMap: nil,
            segments: nil
        )

        do {
            let statusCode = try await sendSinglePayload(payload, event: "test", config: config)
            let isSuccess = (200...299).contains(statusCode)
            deliveryLog.append(
                WebhookDeliveryEntry(
                    deliveredAt: Date(),
                    event: "test",
                    statusCode: statusCode,
                    succeeded: isSuccess,
                    errorMessage: isSuccess ? nil : "HTTP \(statusCode)"
                )
            )
            return statusCode
        } catch {
            deliveryLog.append(
                WebhookDeliveryEntry(
                    deliveredAt: Date(),
                    event: "test",
                    statusCode: statusCode(from: error),
                    succeeded: false,
                    errorMessage: Self.truncatedErrorMessage(error)
                )
            )
            throw error
        }
    }

    public static func signatureHex(secret: String, body: Data) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

private extension WebhookService {
    static func defaultAppVersion() -> String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version.isEmpty == false
        else {
            return "unknown"
        }
        return version
    }

    func makeTranscriptPayload(
        from transcript: TranscriptRecord,
        config: WebhookConfiguration
    ) -> WebhookPayload {
        let mappedSegments: [WebhookSegment]? = config.includeSegments
            ? transcript.segments?.map {
                WebhookSegment(
                    start: $0.start,
                    end: $0.end,
                    text: $0.text,
                    speaker: $0.speaker
                )
            }
            : nil

        return WebhookPayload(
            event: "transcript.created",
            transcriptID: transcript.id,
            createdAt: transcript.createdAt,
            sourceType: transcript.sourceType,
            modelID: transcript.modelID,
            durationSeconds: transcript.durationSeconds,
            text: transcript.text,
            speakerMap: config.includeSpeakerMap ? transcript.speakerMap : nil,
            segments: mappedSegments
        )
    }

    func sendDeliveryPayload(
        _ payload: WebhookPayload,
        event: String,
        config: WebhookConfiguration
    ) async throws -> Int {
        var attempts = 0

        while true {
            do {
                let statusCode = try await sendSinglePayload(payload, event: event, config: config)
                if (200...299).contains(statusCode) {
                    return statusCode
                }

                if shouldRetry(statusCode: statusCode),
                   attempts < Self.retryDelaysNanoseconds.count {
                    let delay = Self.retryDelaysNanoseconds[attempts]
                    attempts += 1
                    await sleep(delay)
                    continue
                }

                throw WebhookServiceError.unexpectedStatusCode(statusCode)
            } catch let error as URLError {
                if attempts < Self.retryDelaysNanoseconds.count {
                    let delay = Self.retryDelaysNanoseconds[attempts]
                    attempts += 1
                    await sleep(delay)
                    continue
                }
                throw error
            }
        }
    }

    func sendSinglePayload(
        _ payload: WebhookPayload,
        event: String,
        config: WebhookConfiguration
    ) async throws -> Int {
        guard let endpointURL = config.validatedEndpointURL else {
            throw WebhookServiceError.invalidEndpointURL
        }

        let body = try encoder.encode(payload)
        var request = URLRequest(url: endpointURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Waffle/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(event, forHTTPHeaderField: "X-Waffle-Event")

        let trimmedSecret = config.hmacSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSecret.isEmpty == false {
            let signature = Self.signatureHex(secret: trimmedSecret, body: body)
            request.setValue("sha256=\(signature)", forHTTPHeaderField: "X-Waffle-Signature")
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebhookServiceError.invalidResponse
        }

        return httpResponse.statusCode
    }

    func shouldRetry(statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }

    func statusCode(from error: Error) -> Int? {
        guard case WebhookServiceError.unexpectedStatusCode(let statusCode) = error else {
            return nil
        }
        return statusCode
    }

    static func truncatedErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.count <= 200 {
            return message
        }
        return String(message.prefix(200))
    }
}
