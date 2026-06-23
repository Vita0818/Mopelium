import XCTest
@testable import MopeliumProviders

final class SSEParserTests: XCTestCase {
    func testParsesOpenAIContentDeltasAndDone() {
        let parser = SSEParser()
        let sample = """
data: {"choices":[{"delta":{"content":"Hel"}}]}

data: {"choices":[{"delta":{"content":"lo"}}]}

data: [DONE]

"""
        let events = parser.consume(Data(sample.utf8)) + parser.flush()
        let text = events.compactMap { event -> String? in
            if case .content(let content) = event { return content }
            return nil
        }.joined()

        XCTAssertEqual(text, "Hello")
        XCTAssertTrue(events.contains(.done))
    }

    func testReassemblesAcrossArbitraryChunks() {
        let parser = SSEParser()
        let sample = """
data: {"choices":[{"delta":{"content":"Hel"}}]}

data: {"choices":[{"delta":{"content":"lo"}}]}

data: [DONE]

"""
        let bytes = Array(sample.utf8)
        var events: [SSEParserEvent] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + 5, bytes.count)
            events += parser.consume(Data(bytes[index..<end]))
            index = end
        }
        events += parser.flush()

        let text = events.compactMap { event -> String? in
            if case .content(let content) = event { return content }
            return nil
        }.joined()
        XCTAssertEqual(text, "Hello")
        XCTAssertTrue(events.contains(.done))
    }

    func testIgnoresCommentsAndEmptyDeltas() {
        let parser = SSEParser()
        let sample = """
: keep-alive

data: {"choices":[{"delta":{}}]}

data: {"choices":[{"delta":{"content":"ok"}}]}

data: [DONE]

"""
        let events = parser.consume(Data(sample.utf8)) + parser.flush()
        XCTAssertEqual(events, [.content("ok"), .done])
    }
}
