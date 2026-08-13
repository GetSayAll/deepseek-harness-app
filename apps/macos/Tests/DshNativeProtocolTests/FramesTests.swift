import XCTest
@testable import DshNativeProtocol

final class FramesTests: XCTestCase {
    func testHelloResponseDecodesProtocolFacts() throws {
        let data = Data(#"{"id":"1","type":"hello","protocolVersion":0,"appVersion":"0.1.0","capabilities":["rpc.unary","rpc.respond","events.mux","events.host"]}"#.utf8)
        let response = try JSONDecoder().decode(HelloResponse.self, from: data)

        XCTAssertEqual(response.protocolVersion, NativeProtocol.version)
        XCTAssertEqual(response.capabilities, NativeProtocol.capabilities)
    }

    func testClientResponseEncodesThePendingRpcId() throws {
        let request = NativeRespondRequest(
            id: "1",
            rpcId: "pending-1",
            result: ClientSuccess(value: ["outcome": "allowed-once"])
        )
        let value = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let result = try XCTUnwrap(value["result"] as? [String: Any])

        XCTAssertEqual(value["type"] as? String, "respond")
        XCTAssertEqual(value["rpcId"] as? String, "pending-1")
        XCTAssertEqual(result["ok"] as? Bool, true)
    }

    func testHostDescriptionDecodesSuccessfulServerResponse() throws {
        let data = Data(#"{"type":"server-response","rpcId":"1","result":{"ok":true,"value":{"version":"0.1.0","cwd":"/tmp","provider":"deepseek-official","model":"deepseek-v4-flash","attachedSessions":0,"canOpenPath":true}}}"#.utf8)
        let response = try JSONDecoder().decode(ServerResponse<HostDescription>.self, from: data)

        guard case let .success(description) = response.result else {
            return XCTFail("Expected a successful Host response")
        }
        XCTAssertEqual(description.cwd, "/tmp")
        XCTAssertTrue(description.canOpenPath)
    }

    func testRpcFailurePreservesCodeAndMessage() throws {
        let data = Data(#"{"type":"server-response","rpcId":"1","result":{"ok":false,"error":{"code":"internal","message":"failed","details":{}}}}"#.utf8)
        let response = try JSONDecoder().decode(ServerResponse<HostDescription>.self, from: data)

        guard case let .failure(code, message) = response.result else {
            return XCTFail("Expected a failed Host response")
        }
        XCTAssertEqual(code, "internal")
        XCTAssertEqual(message, "failed")
    }
}
