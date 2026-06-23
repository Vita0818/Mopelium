import Foundation

public enum SSEParserEvent: Equatable, Sendable {
    case content(String)
    case done
}

private struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta?
    }
    let choices: [Choice]
}

private extension String {
    func trimmingTrailingCR() -> String {
        hasSuffix("\r") ? String(dropLast()) : self
    }
}

public final class SSEParser {
    private var buffer = Data()
    private var dataLines: [String] = []

    public init() {}

    public func consume(_ chunk: Data) -> [SSEParserEvent] {
        buffer.append(chunk)
        var events: [SSEParserEvent] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self).trimmingTrailingCR()

            if line.isEmpty {
                events.append(contentsOf: dispatchPendingEvent())
            } else if line.hasPrefix(":") {
                continue
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst("data:".count))
                if value.hasPrefix(" ") { value.removeFirst() }
                dataLines.append(value)
            }
        }

        return events
    }

    public func flush() -> [SSEParserEvent] {
        dispatchPendingEvent()
    }

    private func dispatchPendingEvent() -> [SSEParserEvent] {
        guard !dataLines.isEmpty else { return [] }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)

        if payload == "[DONE]" {
            return [.done]
        }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
              let content = chunk.choices.first?.delta?.content,
              !content.isEmpty else {
            return []
        }
        return [.content(content)]
    }
}
