import DshNativeProtocol
import XCTest
@testable import DeepSeekHarness

final class APIModelsTests: XCTestCase {
    func testUserVisibleTextAcceptsOnlyDirectUserMessages() throws {
        let user = try decode(#"{"content":[{"type":"text","text":"hello"}],"source":{"kind":"user"}}"#)
        let plugin = try decode(#"{"content":[{"type":"text","text":"internal"}],"source":{"kind":"plugin"}}"#)

        XCTAssertEqual(user.userVisibleText(), "hello")
        XCTAssertEqual(plugin.userVisibleText(), "")
    }

    func testAssistantVisibleTextExcludesReasoningBlocks() throws {
        let message = try decode(#"{"content":[{"type":"reasoning","text":"private reasoning"},{"type":"text","text":"answer"}]}"#)

        XCTAssertEqual(message.assistantVisibleText(), "answer")
    }

    @MainActor
    func testHistoryUsesToolPresentationAndKeepsOrphanResults() throws {
        let call = try decodeEvent(#"{"type":"tool/call","seq":1,"time":1,"data":{"turn":1,"step":1,"callId":"c1","name":"bash","arguments":"{\"command\":\"pwd\"}"}}"#)
        let result = try decodeEvent(#"{"type":"tool/result","seq":2,"time":2,"data":{"turn":1,"step":1,"message":{"role":"user","content":[{"type":"tool-result","toolCallId":"c1","content":[{"type":"text","text":"/tmp"}],"isError":false}],"source":{"kind":"tool","callId":"c1"},"id":"m1"}}}"#)
        let orphanResult = try decodeEvent(#"{"type":"tool/result","seq":3,"time":3,"data":{"turn":1,"step":1,"message":{"role":"user","content":[{"type":"tool-result","toolCallId":"outside","content":[{"type":"text","text":"retained"}],"isError":false}],"source":{"kind":"tool","callId":"outside"},"id":"m2"}}}"#)
        let callView = try JSONDecoder().decode(ToolEventView.self, from: Data(#"{"for":"call","view":{"card":"terminal","title":"pwd","description":"查看目录"}}"#.utf8))

        let items = AppStore.fold([
            .init(event: call, view: callView),
            .init(event: result, view: nil),
            .init(event: orphanResult, view: nil),
        ])
        guard case let .tool(paired) = items[0], case let .tool(orphan) = items[1] else {
            return XCTFail("Expected paired and orphan tool cards")
        }
        XCTAssertEqual(paired.card, "terminal")
        XCTAssertEqual(paired.title, "pwd")
        XCTAssertEqual(paired.detail, "/tmp")
        XCTAssertTrue(paired.completed)
        XCTAssertEqual(orphan.callId, "outside")
        XCTAssertEqual(orphan.detail, "retained")
        XCTAssertTrue(orphan.completed)
    }

    @MainActor
    func testPendingInteractionsDecodeWirePayloads() throws {
        let approvalPayload = try decode(#"{"sessionId":"s","approvalId":"a","toolName":"bash","callId":"c","reason":"需要权限"}"#).objectValue!
        let questionPayload = try decode(#"{"sessionId":"s","questions":[{"id":"targets","question":"选择目标","header":"范围","options":[{"label":"代码","description":"修改源代码"},{"label":"文档"}],"multiSelect":true}]}"#).objectValue!

        let approval = try XCTUnwrap(AppStore.approval(rpcId: "r1", payload: approvalPayload))
        let question = try XCTUnwrap(AppStore.question(rpcId: "r2", payload: questionPayload))

        XCTAssertEqual(approval.callId, "c")
        XCTAssertEqual(approval.reason, "需要权限")
        XCTAssertEqual(question.questions.first?.header, "范围")
        XCTAssertEqual(question.questions.first?.options.first?.description, "修改源代码")
        XCTAssertTrue(question.questions.first?.multiSelect == true)
    }

    func testQuestionResponseEncodesStructuredAnswers() throws {
        let payload = QuestionResponsePayload(
            sessionId: "s",
            answer: .init(answers: [.init(id: "targets", selected: ["代码"], custom: "测试")])
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        let answer = try XCTUnwrap(object["answer"] as? [String: Any])
        let answers = try XCTUnwrap(answer["answers"] as? [[String: Any]])

        XCTAssertEqual(object["sessionId"] as? String, "s")
        XCTAssertEqual(answers.first?["selected"] as? [String], ["代码"])
        XCTAssertEqual(answers.first?["custom"] as? String, "测试")
    }

    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func decodeEvent(_ json: String) throws -> SessionEvent {
        try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
    }
}
