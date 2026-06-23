import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatRequest: Equatable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var stream: Bool

    public init(model: String, messages: [ChatMessage], stream: Bool) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

public struct ChatChunk: Equatable, Sendable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public struct ChatResponse: Equatable, Sendable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public protocol ChatProvider: Sendable {
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, Error>
    func complete(request: ChatRequest) async throws -> ChatResponse
}
