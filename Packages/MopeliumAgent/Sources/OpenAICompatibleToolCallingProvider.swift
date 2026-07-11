import Foundation
import MopeliumCore
import MopeliumProviders
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAICompatibleToolCallingProvider: ToolCallingChatProvider {
    public let baseURL: URL
    public let apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public init(provider: OpenAICompatibleProvider) {
        self.baseURL = provider.baseURL
        self.apiKey = provider.apiKey
    }

    public func streamToolCalls(request: ToolChatRequest) async throws -> AsyncThrowingStream<ToolChatChunk, Error> {
        let urlRequest = try buildURLRequest(for: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(Darwin)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        let body = try await collectBodyPrefix(from: bytes)
                        throw MopeliumError.httpStatus(http.statusCode, providerErrorMessage(from: body))
                    }

                    let parser = OpenAIToolCallSSEParser()
                    var line = Data()
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == 0x0A {
                            for chunk in try parser.consume(line) {
                                continuation.yield(chunk)
                                if case .done = chunk {
                                    continuation.finish()
                                    return
                                }
                            }
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if !line.isEmpty {
                        for chunk in try parser.consume(line) {
                            continuation.yield(chunk)
                        }
                    }
                    for chunk in try parser.flush() {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    #else
                    throw MopeliumError.network("Streaming HTTP is unavailable on this platform.")
                    #endif
                } catch {
                    continuation.finish(throwing: mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildURLRequest(for request: ToolChatRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let body = OpenAIToolChatRequestBody(
                model: request.model,
                messages: request.messages.map(Self.messageJSON),
                tools: request.tools.map(Self.toolJSON),
                stream: true
            )
            urlRequest.httpBody = try JSONEncoder().encode(body)
            return urlRequest
        } catch {
            throw MopeliumError.decoding("cannot encode tool-calling request body: \(error.localizedDescription)")
        }
    }

    static func messageJSON(_ message: ToolChatMessage) -> OpenAIToolChatMessageBody {
        let toolCalls = message.toolCalls?.map { toolCall in
            OpenAIToolCallBody(
                id: toolCall.id,
                type: "function",
                function: OpenAIToolCallFunctionBody(name: toolCall.name, arguments: toolCall.arguments)
            )
        }
        return OpenAIToolChatMessageBody(
            role: message.role.rawValue,
            content: message.content,
            tool_calls: toolCalls,
            tool_call_id: message.toolCallId
        )
    }

    private static func toolJSON(_ tool: ToolSpec) -> OpenAIToolDefinitionBody {
        OpenAIToolDefinitionBody(
            type: "function",
            function: OpenAIToolFunctionDefinitionBody(
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters
            )
        )
    }

    #if canImport(Darwin)
    private func collectBodyPrefix(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count < 4096 {
                data.append(byte)
            }
        }
        return data
    }
    #endif

    private func providerErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return truncated(message, limit: 500)
            }
            if let message = object["message"] as? String {
                return truncated(message, limit: 500)
            }
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return truncated(text, limit: 500)
    }

    private func mapError(_ error: Error) -> Error {
        if let mopeliumError = error as? MopeliumError { return mopeliumError }
        if let urlError = error as? URLError { return MopeliumError.network(urlError.localizedDescription) }
        if let decodingError = error as? DecodingError { return MopeliumError.decoding("\(decodingError)") }
        return MopeliumError.provider(error.localizedDescription)
    }
}

final class OpenAIToolCallSSEParser {
    private var buffer = Data()
    private var dataLines: [String] = []
    private var accumulators: [ToolCallAccumKey: ToolCallAccum] = [:]
    private var emittedDone = false

    func consume(_ chunk: Data) throws -> [ToolChatChunk] {
        buffer.append(chunk)
        var chunks: [ToolChatChunk] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self).trimmingTrailingCRForToolCalling()

            if line.isEmpty {
                chunks.append(contentsOf: try dispatchPendingEvent())
            } else if line.hasPrefix(":") {
                continue
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst("data:".count))
                if value.hasPrefix(" ") { value.removeFirst() }
                dataLines.append(value)
            }
        }

        return chunks
    }

    func flush() throws -> [ToolChatChunk] {
        try dispatchPendingEvent()
    }

    private func dispatchPendingEvent() throws -> [ToolChatChunk] {
        guard !dataLines.isEmpty else { return [] }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)

        if payload == "[DONE]" {
            if emittedDone { return [] }
            emittedDone = true
            return [.done(finishReason: nil)]
        }

        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "provider error"
            throw MopeliumError.provider(truncated(message, limit: 500))
        }

        let chunk: OpenAIToolStreamChunk
        do {
            chunk = try JSONDecoder().decode(OpenAIToolStreamChunk.self, from: data)
        } catch {
            throw MopeliumError.decoding("invalid tool-calling stream payload: \(truncated(trimmed, limit: 500)); \(error)")
        }

        var output: [ToolChatChunk] = []
        var finishReason: String?
        if let choices = chunk.choices {
            for (choiceOffset, choice) in choices.enumerated() {
                let choiceIndex = choice.index ?? choiceOffset
                if let content = choice.delta?.content, !content.isEmpty {
                    output.append(.textDelta(content))
                }
                if let fragments = choice.delta?.tool_calls {
                    for (toolOffset, fragment) in fragments.enumerated() {
                        let key = ToolCallAccumKey(choiceIndex: choiceIndex, toolIndex: fragment.index ?? toolOffset)
                        var entry = accumulators[key] ?? ToolCallAccum()
                        if let id = fragment.id { entry.id = id }
                        if let function = fragment.function {
                            if let name = function.name { entry.name = name }
                            if let arguments = function.arguments { entry.arguments += arguments }
                        }
                        accumulators[key] = entry
                    }
                }
                if let reason = choice.finish_reason {
                    finishReason = preferredFinishReason(finishReason, reason)
                }
            }
        }

        if let reason = finishReason, !emittedDone {
            let calls = try completedToolCalls(finishReason: reason)
            if !calls.isEmpty {
                output.append(.toolCalls(calls))
            }
            output.append(.done(finishReason: reason))
            emittedDone = true
        }

        return output
    }

    private func preferredFinishReason(_ current: String?, _ candidate: String) -> String {
        if candidate == "tool_calls" || candidate == "function_call" {
            return candidate
        }
        return current ?? candidate
    }

    private func completedToolCalls(finishReason: String) throws -> [ToolCall] {
        let keys = accumulators.keys.sorted()
        if (finishReason == "tool_calls" || finishReason == "function_call"), keys.isEmpty {
            throw MopeliumError.provider("provider tool-call stream was incomplete: finished with \(finishReason) but emitted no tool call deltas")
        }

        let missingNames = keys.filter { key in
            guard let entry = accumulators[key] else { return true }
            return entry.name.isEmpty
        }
        if !missingNames.isEmpty {
            let indexes = missingNames.map { "\($0.choiceIndex):\($0.toolIndex)" }.joined(separator: ", ")
            throw MopeliumError.provider("provider tool-call stream was incomplete: omitted tool names for choice/tool index \(indexes)")
        }

        return try keys.map { key in
            guard let entry = accumulators[key], !entry.name.isEmpty else {
                throw MopeliumError.provider("provider tool-call stream was incomplete: omitted tool name")
            }
            let id = entry.id.isEmpty
                ? (key.choiceIndex == 0 ? "call_\(key.toolIndex)" : "call_\(key.choiceIndex)_\(key.toolIndex)")
                : entry.id
            let arguments = try validatedArguments(entry.arguments, key: key, finishReason: finishReason)
            return ToolCall(id: id, name: entry.name, arguments: arguments)
        }
    }

    private func validatedArguments(_ arguments: String, key: ToolCallAccumKey, finishReason: String) throws -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return arguments }
        guard let data = trimmed.data(using: .utf8) else {
            throw MopeliumError.provider("provider tool-call stream was incomplete: non-UTF-8 arguments for choice/tool index \(key.choiceIndex):\(key.toolIndex)")
        }
        do {
            _ = try JSONDecoder().decode(JSONSchemaValue.self, from: data)
        } catch {
            throw MopeliumError.provider("provider tool-call stream was incomplete: invalid JSON arguments for choice/tool index \(key.choiceIndex):\(key.toolIndex) at \(finishReason)")
        }
        return arguments
    }
}

private struct OpenAIToolStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let tool_calls: [ToolCallFragment]?
        }

        struct ToolCallFragment: Decodable {
            struct Function: Decodable {
                let name: String?
                let arguments: String?

                enum CodingKeys: String, CodingKey {
                    case name
                    case arguments
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    if let stringArguments = try? container.decodeIfPresent(String.self, forKey: .arguments) {
                        arguments = stringArguments
                    } else if container.contains(.arguments) {
                        let value = try container.decode(JSONSchemaValue.self, forKey: .arguments)
                        arguments = try Self.argumentString(from: value)
                    } else {
                        arguments = nil
                    }
                }

                private static func argumentString(from value: JSONSchemaValue) throws -> String? {
                    if value == .null { return nil }
                    let data = try JSONEncoder().encode(value)
                    return String(data: data, encoding: .utf8)
                }
            }

            let index: Int?
            let id: String?
            let function: Function?

            enum CodingKeys: String, CodingKey {
                case index
                case id
                case function
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let intIndex = try? container.decodeIfPresent(Int.self, forKey: .index) {
                    index = intIndex
                } else if let stringIndex = try? container.decodeIfPresent(String.self, forKey: .index),
                          let parsed = Int(stringIndex) {
                    index = parsed
                } else {
                    index = nil
                }
                id = try container.decodeIfPresent(String.self, forKey: .id)
                function = try container.decodeIfPresent(Function.self, forKey: .function)
            }
        }

        let index: Int?
        let delta: Delta?
        let finish_reason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finish_reason
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intIndex = try? container.decodeIfPresent(Int.self, forKey: .index) {
                index = intIndex
            } else if let stringIndex = try? container.decodeIfPresent(String.self, forKey: .index),
                      let parsed = Int(stringIndex) {
                index = parsed
            } else {
                index = nil
            }
            delta = try container.decodeIfPresent(Delta.self, forKey: .delta)
            finish_reason = try container.decodeIfPresent(String.self, forKey: .finish_reason)
        }
    }

    let choices: [Choice]?
}

private struct ToolCallAccum {
    var id = ""
    var name = ""
    var arguments = ""
}

private struct ToolCallAccumKey: Comparable, Hashable {
    var choiceIndex: Int
    var toolIndex: Int

    static func < (lhs: ToolCallAccumKey, rhs: ToolCallAccumKey) -> Bool {
        if lhs.choiceIndex != rhs.choiceIndex {
            return lhs.choiceIndex < rhs.choiceIndex
        }
        return lhs.toolIndex < rhs.toolIndex
    }
}

private extension String {
    func trimmingTrailingCRForToolCalling() -> String {
        hasSuffix("\r") ? String(dropLast()) : self
    }
}

struct OpenAIToolChatMessageBody: Encodable {
    let role: String
    let content: String?
    let tool_calls: [OpenAIToolCallBody]?
    let tool_call_id: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let content {
            try container.encode(content, forKey: .content)
        } else if role == "assistant", tool_calls != nil {
            try container.encodeNil(forKey: .content)
        }
        try container.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case tool_calls
        case tool_call_id
    }
}

struct OpenAIToolCallBody: Encodable {
    let id: String
    let type: String
    let function: OpenAIToolCallFunctionBody
}

struct OpenAIToolCallFunctionBody: Encodable {
    let name: String
    let arguments: String
}

private struct OpenAIToolChatRequestBody: Encodable {
    let model: String
    let messages: [OpenAIToolChatMessageBody]
    let tools: [OpenAIToolDefinitionBody]
    let stream: Bool
}

private struct OpenAIToolDefinitionBody: Encodable {
    let type: String
    let function: OpenAIToolFunctionDefinitionBody
}

private struct OpenAIToolFunctionDefinitionBody: Encodable {
    let name: String
    let description: String
    let parameters: JSONSchemaValue
}
