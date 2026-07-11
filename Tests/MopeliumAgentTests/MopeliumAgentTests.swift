import XCTest
@testable import MopeliumAgent
import MopeliumProviders
import MopeliumTools

final class ScriptedToolProvider: ToolCallingChatProvider, @unchecked Sendable {
    private let state: ScriptedToolProviderState

    init(_ scripts: [[ToolChatChunk]]) {
        self.state = ScriptedToolProviderState(scripts)
    }

    func capturedRequests() async -> [ToolChatRequest] {
        await state.capturedRequests()
    }

    func streamToolCalls(request: ToolChatRequest) async throws -> AsyncThrowingStream<ToolChatChunk, Error> {
        let script = await state.nextScript(for: request)
        return AsyncThrowingStream { continuation in
            for chunk in script {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private actor ScriptedToolProviderState {
    private var scripts: [[ToolChatChunk]]
    private var requests: [ToolChatRequest] = []

    init(_ scripts: [[ToolChatChunk]]) {
        self.scripts = scripts
    }

    func capturedRequests() -> [ToolChatRequest] {
        requests
    }

    func nextScript(for request: ToolChatRequest) -> [ToolChatChunk] {
        requests.append(request)
        if scripts.isEmpty {
            return [.done(finishReason: "stop")]
        }
        return scripts.removeFirst()
    }
}

final class MopeliumAgentTests: XCTestCase {
    func testAgentLoopRunsToolAndFeedsObservationBackToModel() async throws {
        let workspace = try tempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let provider = ScriptedToolProvider([
            [
                .toolCalls([ToolCall(id: "write", name: "write_file", arguments: #"{"path":"out.txt","content":"hello"}"#)]),
                .done(finishReason: "tool_calls"),
            ],
            [
                .textDelta("done"),
                .done(finishReason: "stop"),
            ],
        ])
        let loop = MopeliumAgentLoop(
            provider: provider,
            workspaceRoot: workspace,
            policy: MopeliumAgentToolPolicy(
                allowedSideEffects: [.readOnly, .write],
                allowShellTool: false
            )
        )

        var text = ""
        var toolResults: [String] = []
        for try await event in loop.stream(model: "test-model", messages: [ChatMessage(role: "user", content: "write a file")]) {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .toolResult(_, _, let observation, _):
                toolResults.append(observation)
            case .toolCall:
                break
            }
        }

        XCTAssertEqual(text, "done")
        XCTAssertTrue(toolResults.first?.contains("out.txt") == true, toolResults.joined())
        let content = try String(contentsOf: workspace.appendingPathComponent("out.txt"), encoding: .utf8)
        XCTAssertEqual(content, "hello")

        let requests = await provider.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].messages.contains { message in
            message.role == .tool && (message.content?.contains("out.txt") ?? false)
        })
    }

    func testAgentLoopDeniesDisallowedWriteToolBeforeExecution() async throws {
        let workspace = try tempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let provider = ScriptedToolProvider([
            [
                .toolCalls([ToolCall(id: "write", name: "write_file", arguments: #"{"path":"out.txt","content":"hello"}"#)]),
                .done(finishReason: "tool_calls"),
            ],
            [
                .textDelta("blocked"),
                .done(finishReason: "stop"),
            ],
        ])
        let loop = MopeliumAgentLoop(
            provider: provider,
            workspaceRoot: workspace,
            policy: .readOnly
        )

        var observations: [String] = []
        for try await event in loop.stream(model: "test-model", messages: [ChatMessage(role: "user", content: "write a file")]) {
            if case .toolResult(_, _, let observation, _) = event {
                observations.append(observation)
            }
        }

        XCTAssertTrue(observations.first?.contains("permission denied") == true, observations.joined())
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("out.txt").path))
    }

    private func tempWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mopelium-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
