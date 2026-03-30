import Foundation

public struct PromptTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.createdAt = createdAt
    }
}

public final class PromptTemplateStore: @unchecked Sendable {
    public static let storageKey = "promptTemplates"
    public static let maxTemplateCount = 20

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

    public func load() -> [PromptTemplate] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            let defaults = Self.defaultTemplates()
            save(defaults)
            return defaults
        }

        do {
            return try decoder.decode([PromptTemplate].self, from: data)
        } catch {
            return []
        }
    }

    public func save(_ templates: [PromptTemplate]) {
        guard let data = try? encoder.encode(templates) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    @discardableResult
    public func add(name: String, prompt: String) -> PromptTemplate {
        let template = PromptTemplate(
            name: name,
            prompt: prompt,
            createdAt: Date()
        )
        var templates = load()
        templates.append(template)
        save(templates)
        return template
    }

    public func update(_ template: PromptTemplate) {
        var templates = load()
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        save(templates)
    }

    public func delete(id: UUID) {
        var templates = load()
        templates.removeAll { $0.id == id }
        save(templates)
    }

    public static func defaultTemplates() -> [PromptTemplate] {
        [
            PromptTemplate(
                name: "Bullet Summary",
                prompt: "Summarize this transcript in 5 concise bullet points."
            ),
            PromptTemplate(
                name: "Action Items",
                prompt: "List all action items and assigned owners from this transcript."
            ),
            PromptTemplate(
                name: "Key Topics",
                prompt: "What are the 3 most important topics discussed in this transcript?"
            ),
        ]
    }
}
