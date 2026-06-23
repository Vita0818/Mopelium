import Foundation
import MopeliumCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAICompatibleProvider: ChatProvider {
    public let baseURL: URL
    public let apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        var streamingRequest = request
        streamingRequest.stream = true
        let urlRequest = try buildURLRequest(for: streamingRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(Darwin)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        let body = try await collectBodyPrefix(from: bytes)
                        throw MopeliumError.httpStatus(http.statusCode, Self.providerErrorMessage(from: body))
                    }

                    let parser = SSEParser()
                    var line = Data()
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == 0x0A {
                            if emit(parser.consume(line), to: continuation) { return }
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if !line.isEmpty {
                        if emit(parser.consume(line), to: continuation) { return }
                    }
                    _ = emit(parser.flush(), to: continuation)
                    continuation.finish()
                    #else
                    throw MopeliumError.network("Streaming HTTP is unavailable on this platform.")
                    #endif
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func complete(request: ChatRequest) async throws -> ChatResponse {
        var nonStreamingRequest = request
        nonStreamingRequest.stream = false
        let urlRequest = try buildURLRequest(for: nonStreamingRequest)

        do {
            #if canImport(Darwin)
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw MopeliumError.httpStatus(http.statusCode, Self.providerErrorMessage(from: data))
            }
            let decoded = try JSONDecoder().decode(OpenAICompleteResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw MopeliumError.provider("empty response")
            }
            return ChatResponse(content: content)
            #else
            throw MopeliumError.network("HTTP is unavailable on this platform.")
            #endif
        } catch {
            throw Self.mapError(error)
        }
    }

    private func buildURLRequest(for request: ChatRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let body = OpenAIChatRequestBody(
                model: request.model,
                messages: request.messages,
                stream: request.stream
            )
            urlRequest.httpBody = try JSONEncoder().encode(body)
            return urlRequest
        } catch {
            throw MopeliumError.decoding("cannot encode request body: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func emit(_ events: [SSEParserEvent], to continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) -> Bool {
        for event in events {
            switch event {
            case .content(let content):
                continuation.yield(ChatChunk(content: content))
            case .done:
                continuation.finish()
                return true
            }
        }
        return false
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

    private static func providerErrorMessage(from data: Data) -> String? {
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

    private static func mapError(_ error: Error) -> Error {
        if let mopeliumError = error as? MopeliumError { return mopeliumError }
        if let urlError = error as? URLError { return MopeliumError.network(urlError.localizedDescription) }
        if let decodingError = error as? DecodingError { return MopeliumError.decoding("\(decodingError)") }
        return MopeliumError.provider(error.localizedDescription)
    }
}

private struct OpenAIChatRequestBody: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct OpenAICompleteResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
