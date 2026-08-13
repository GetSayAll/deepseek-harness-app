import XCTest
@testable import DeepSeekHarness

final class HostProcessTests: XCTestCase {
    func testStartsTheRealSidecarAndNegotiatesHello() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        setenv("DSH_MACOS_REPOSITORY_ROOT", repositoryRoot.path, 1)
        defer { unsetenv("DSH_MACOS_REPOSITORY_ROOT") }

        let host = HostProcess()
        let hello = try await host.start()
        await host.stop()

        XCTAssertEqual(hello.protocolVersion, 0)
        XCTAssertTrue(hello.capabilities.contains("rpc.unary"))
        XCTAssertTrue(hello.capabilities.contains("rpc.respond"))
    }
}
