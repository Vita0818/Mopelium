import Foundation
import MopeliumCore
import MopeliumProviders
import MopeliumTools

public struct MopeliumAgentToolPolicy: Sendable {
    public var allowedSideEffects: Set<SideEffect>
    public var allowShellTool: Bool
    public var maxIterations: Int
    public var maxObservationCharacters: Int

    public init(allowedSideEffects: Set<SideEffect>,
                allowShellTool: Bool = false,
                maxIterations: Int = 12,
                maxObservationCharacters: Int = 12_000) {
        self.allowedSideEffects = allowedSideEffects
        self.allowShellTool = allowShellTool
        self.maxIterations = maxIterations
        self.maxObservationCharacters = maxObservationCharacters
    }

    public static let browserRead = MopeliumAgentToolPolicy(
        allowedSideEffects: [.readOnly, .network, .exec],
        allowShellTool: false
    )

    public static let readOnly = MopeliumAgentToolPolicy(
        allowedSideEffects: [.readOnly],
        allowShellTool: false
    )

    public static let all = MopeliumAgentToolPolicy(
        allowedSideEffects: [.readOnly, .network, .exec, .write, .destructive],
        allowShellTool: true
    )

    func exposes(_ descriptor: ToolDescriptor) -> Bool {
        allows(descriptor, toolName: descriptor.name)
    }

    func allows(_ descriptor: ToolDescriptor, toolName: String) -> Bool {
        guard allowedSideEffects.contains(descriptor.sideEffect) else { return false }
        if toolName == "run_shell", !allowShellTool { return false }
        return true
    }
}

public enum MopeliumAgentEvent: Sendable, Equatable {
    case textDelta(String)
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, name: String, observation: String, changedFiles: [String])
}

public struct MopeliumAgentLoop: Sendable {
    private let provider: any ToolCallingChatProvider
    private let registry: ToolRegistry
    private let workspaceRoot: URL
    private let policy: MopeliumAgentToolPolicy

    public init(provider: any ToolCallingChatProvider,
                registry: ToolRegistry = .standard(),
                workspaceRoot: URL,
                policy: MopeliumAgentToolPolicy = .browserRead) {
        self.provider = provider
        self.registry = registry
        self.workspaceRoot = workspaceRoot
        self.policy = policy
    }

    public func stream(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<MopeliumAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(model: model, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(model: String,
                     messages: [ChatMessage],
                     continuation: AsyncThrowingStream<MopeliumAgentEvent, Error>.Continuation) async throws {
        var conversation = initialMessages(from: messages)
        let specs = toolSpecs()
        guard !specs.isEmpty else {
            throw MopeliumError.config("No tools are allowed by the current tool policy.")
        }

        for _ in 0..<policy.maxIterations {
            var assistantText = ""
            var pendingToolCalls: [ToolCall] = []
            let request = ToolChatRequest(model: model, messages: conversation, tools: specs)
            let chunks = try await provider.streamToolCalls(request: request)

            for try await chunk in chunks {
                if Task.isCancelled { throw CancellationError() }
                switch chunk {
                case .textDelta(let delta):
                    assistantText += delta
                    continuation.yield(.textDelta(delta))
                case .toolCalls(let calls):
                    pendingToolCalls = calls
                case .done:
                    break
                }
            }

            guard !pendingToolCalls.isEmpty else { return }

            conversation.append(.assistant(
                toolCalls: pendingToolCalls,
                content: assistantText.isEmpty ? nil : assistantText
            ))

            for toolCall in pendingToolCalls {
                if Task.isCancelled { throw CancellationError() }
                continuation.yield(.toolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                let result = await runTool(toolCall)
                continuation.yield(.toolResult(
                    id: toolCall.id,
                    name: toolCall.name,
                    observation: result.observation,
                    changedFiles: result.changedFiles
                ))
                conversation.append(.tool(id: toolCall.id, content: result.observation))
            }
        }

        throw MopeliumError.provider("agent exceeded max tool iterations (\(policy.maxIterations))")
    }

    private func initialMessages(from messages: [ChatMessage]) -> [ToolChatMessage] {
        var converted: [ToolChatMessage] = [
            .system("""
            You can call Mopelium tools when they are useful. Tool paths are relative to the selected workspace. Do not request secrets, credentials, cookies, tokens, private keys, or .env contents. Prefer bounded reads and summarize large observations.
            """)
        ]
        converted += messages.compactMap { message in
            switch message.role {
            case "system":
                return .system(message.content)
            case "assistant":
                return .assistant(message.content)
            case "user":
                return .user(message.content)
            default:
                return ToolChatMessage(role: ToolChatRole(rawValue: message.role) ?? .user, content: message.content)
            }
        }
        return converted
    }

    private func toolSpecs() -> [ToolSpec] {
        registry.descriptors()
            .filter { policy.exposes($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { descriptor in
                ToolSpec(
                    name: descriptor.name,
                    description: descriptor.description,
                    parameters: JSONSchemaValue(descriptor.parameters)
                )
            }
    }

    private struct ToolRunResult: Sendable {
        var observation: String
        var changedFiles: [String]
    }

    private func runTool(_ toolCall: ToolCall) async -> ToolRunResult {
        guard let tool = registry.tool(named: toolCall.name) else {
            let available = registry.descriptors().map(\.name).sorted().joined(separator: ", ")
            return ToolRunResult(
                observation: "unknown tool: \(toolCall.name). Available tools: \(available)",
                changedFiles: []
            )
        }

        let descriptor = type(of: tool).descriptor
        guard policy.allows(descriptor, toolName: toolCall.name) else {
            return ToolRunResult(
                observation: "permission denied: \(toolCall.name) has side effect \(descriptor.sideEffect.rawValue) and is not allowed by the current tool policy.",
                changedFiles: []
            )
        }

        let normalizedArguments: String
        switch normalizeToolArguments(toolCall.arguments, descriptor: descriptor) {
        case .valid(let arguments):
            normalizedArguments = arguments
        case .invalid(let message):
            return ToolRunResult(observation: message, changedFiles: [])
        }

        do {
            let args = ToolArgs(raw: normalizedArguments)
            let observation = try await tool.execute(args, in: ToolContext(workspaceRoot: workspaceRoot))
            let text = truncated(observation.text, limit: policy.maxObservationCharacters)
            return ToolRunResult(observation: text, changedFiles: observation.changedFiles ?? [])
        } catch {
            return ToolRunResult(observation: "tool error: \(error.localizedDescription)", changedFiles: [])
        }
    }

    private enum ToolArgumentNormalization {
        case valid(String)
        case invalid(String)
    }

    private func normalizeToolArguments(_ raw: String, descriptor: ToolDescriptor) -> ToolArgumentNormalization {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowsEmptyObject = requiredArguments(in: descriptor).isEmpty

        guard !trimmed.isEmpty else {
            if allowsEmptyObject { return .valid("{}") }
            return .invalid("invalid tool input: arguments for \(descriptor.name) must be a JSON object matching the tool schema; received empty arguments.")
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .invalid("invalid tool input: arguments for \(descriptor.name) are not valid UTF-8.")
        }

        do {
            let value = try JSONDecoder().decode(MopeliumTools.JSONValue.self, from: data)
            switch value {
            case .object(let object):
                if let message = validateToolArgumentObject(object, descriptor: descriptor) {
                    return .invalid(message)
                }
                return .valid(trimmed)
            case .null where allowsEmptyObject:
                return .valid("{}")
            default:
                return .invalid("invalid tool input: arguments for \(descriptor.name) must be a JSON object matching the tool schema.")
            }
        } catch {
            return .invalid("invalid tool input: arguments for \(descriptor.name) must be valid JSON. \(error.localizedDescription)")
        }
    }

    private func validateToolArgumentObject(_ object: [String: MopeliumTools.JSONValue], descriptor: ToolDescriptor) -> String? {
        let required = Set(requiredArguments(in: descriptor))
        let missing = required.filter { object[$0] == nil }.sorted()
        if !missing.isEmpty {
            return "invalid tool input: arguments for \(descriptor.name) are missing required field(s): \(missing.joined(separator: ", "))."
        }

        if rejectsAdditionalProperties(in: descriptor) {
            let allowed = Set(propertyNames(in: descriptor))
            let unknown = object.keys.filter { !allowed.contains($0) }.sorted()
            if !unknown.isEmpty {
                let allowedText = allowed.isEmpty ? "no fields" : allowed.sorted().joined(separator: ", ")
                return "invalid tool input: arguments for \(descriptor.name) contain unknown field(s): \(unknown.joined(separator: ", ")). Allowed fields: \(allowedText)."
            }
        }

        for (name, value) in object.sorted(by: { $0.key < $1.key }) {
            guard let propertySchema = propertySchema(named: name, in: descriptor),
                  let expected = propertyType(in: propertySchema) else { continue }
            if value == .null, !required.contains(name) { continue }
            if !matches(value, expectedType: expected) {
                return "invalid tool input: argument \(name) for \(descriptor.name) must be \(expected)."
            }
        }
        return nil
    }

    private func requiredArguments(in descriptor: ToolDescriptor) -> [String] {
        guard case .object(let schema) = descriptor.parameters,
              case .array(let required)? = schema["required"] else { return [] }
        return required.compactMap { value in
            guard case .string(let name) = value else { return nil }
            return name
        }
    }

    private func propertyNames(in descriptor: ToolDescriptor) -> [String] {
        guard case .object(let schema) = descriptor.parameters,
              case .object(let properties)? = schema["properties"] else { return [] }
        return Array(properties.keys)
    }

    private func rejectsAdditionalProperties(in descriptor: ToolDescriptor) -> Bool {
        guard case .object(let schema) = descriptor.parameters,
              case .bool(let value)? = schema["additionalProperties"] else { return false }
        return value == false
    }

    private func propertySchema(named name: String, in descriptor: ToolDescriptor) -> [String: MopeliumTools.JSONValue]? {
        guard case .object(let schema) = descriptor.parameters,
              case .object(let properties)? = schema["properties"],
              case .object(let propertySchema)? = properties[name] else { return nil }
        return propertySchema
    }

    private func propertyType(in propertySchema: [String: MopeliumTools.JSONValue]) -> String? {
        guard case .string(let type)? = propertySchema["type"] else { return nil }
        return type
    }

    private func matches(_ value: MopeliumTools.JSONValue, expectedType: String) -> Bool {
        switch expectedType {
        case "string":
            if case .string = value { return true }
            return false
        case "integer":
            guard case .number(let number) = value else { return false }
            return number.rounded(.towardZero) == number
        case "number":
            if case .number = value { return true }
            return false
        case "boolean":
            if case .bool = value { return true }
            return false
        case "array":
            if case .array = value { return true }
            return false
        case "object":
            if case .object = value { return true }
            return false
        default:
            return true
        }
    }
}

private extension JSONSchemaValue {
    init(_ value: MopeliumTools.JSONValue) {
        switch value {
        case .null:
            self = .null
        case .bool(let bool):
            self = .bool(bool)
        case .number(let number):
            self = .number(number)
        case .string(let string):
            self = .string(string)
        case .array(let array):
            self = .array(array.map(JSONSchemaValue.init))
        case .object(let object):
            self = .object(object.mapValues(JSONSchemaValue.init))
        }
    }
}
