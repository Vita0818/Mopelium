import Foundation

public enum MopeliumToolError: Error, Sendable, Equatable, LocalizedError {
    case config(String)
    case provider(String)
    case decoding(String)
    case io(String)
    case notFound(String)
    case permissionDenied(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .config(let message):
            return "Configuration error: \(message)"
        case .provider(let message):
            return "Provider error: \(message)"
        case .decoding(let message):
            return "Decoding error: \(message)"
        case .io(let message):
            return "I/O error: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .cancelled:
            return "Cancelled."
        }
    }
}

public enum SideEffect: String, Codable, Hashable, Sendable {
    case readOnly = "read_only"
    case write
    case exec
    case network
    case destructive
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

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
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
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

public extension JSONValue {
    static func obj(_ dict: [String: JSONValue]) -> JSONValue { .object(dict) }
    static func str(_ value: String) -> JSONValue { .string(value) }
}
