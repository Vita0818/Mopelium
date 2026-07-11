import Foundation

public enum JSONSchemaValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONSchemaValue])
    case object([String: JSONSchemaValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONSchemaValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONSchemaValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON schema value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct ToolSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONSchemaValue

    public init(name: String, description: String, parameters: JSONSchemaValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public enum ToolChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ToolChatMessage: Equatable, Sendable {
    public var role: ToolChatRole
    public var content: String?
    public var toolCalls: [ToolCall]?
    public var toolCallId: String?

    public init(role: ToolChatRole, content: String? = nil, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    public static func system(_ text: String) -> ToolChatMessage {
        ToolChatMessage(role: .system, content: text)
    }

    public static func user(_ text: String) -> ToolChatMessage {
        ToolChatMessage(role: .user, content: text)
    }

    public static func assistant(_ text: String) -> ToolChatMessage {
        ToolChatMessage(role: .assistant, content: text)
    }

    public static func assistant(toolCalls: [ToolCall], content: String? = nil) -> ToolChatMessage {
        ToolChatMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    public static func tool(id: String, content: String) -> ToolChatMessage {
        ToolChatMessage(role: .tool, content: content, toolCallId: id)
    }
}

public struct ToolChatRequest: Sendable {
    public var model: String
    public var messages: [ToolChatMessage]
    public var tools: [ToolSpec]

    public init(model: String, messages: [ToolChatMessage], tools: [ToolSpec]) {
        self.model = model
        self.messages = messages
        self.tools = tools
    }
}

public enum ToolChatChunk: Equatable, Sendable {
    case textDelta(String)
    case toolCalls([ToolCall])
    case done(finishReason: String?)
}

public protocol ToolCallingChatProvider: Sendable {
    func streamToolCalls(request: ToolChatRequest) async throws -> AsyncThrowingStream<ToolChatChunk, Error>
}
