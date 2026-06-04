import XCTest
@testable import Redline

final class SmokeTests: XCTestCase {
    func testSampleDataLoads() {
        XCTAssertFalse(SampleData.documents.isEmpty, "bundled samples should exist")
    }

    func testRunnerUsesSourceCheckoutCommandWhenPyprojectExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = FileManager.default.createFile(
            atPath: root.appendingPathComponent("pyproject.toml").path,
            contents: Data()
        )

        let runner = RedlineRunner(repoRoot: root)

        XCTAssertEqual(runner.commandPrefix(), ["uv", "run", "redline", "check"])
        XCTAssertEqual(runner.workingDirectoryURL(), root)
    }

    func testRunnerFallsBackToInstalledCLIOutsideSourceCheckout() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = RedlineRunner(repoRoot: root)

        XCTAssertEqual(runner.commandPrefix(), ["redline", "check"])
        XCTAssertEqual(runner.workingDirectoryURL(), FileManager.default.homeDirectoryForCurrentUser)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
