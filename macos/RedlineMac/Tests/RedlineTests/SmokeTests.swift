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

        let runner = RedlineRunner(repoRoot: root, bundledEngineRoot: nil)

        XCTAssertEqual(runner.commandPrefix(), ["uv", "run", "redline", "check"])
        XCTAssertEqual(runner.workingDirectoryURL(), root)
    }

    func testRunnerFallsBackToInstalledCLIOutsideSourceCheckout() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = RedlineRunner(repoRoot: root, bundledEngineRoot: nil)

        XCTAssertEqual(runner.commandPrefix(), ["redline", "check"])
        XCTAssertEqual(runner.workingDirectoryURL(), FileManager.default.homeDirectoryForCurrentUser)
    }

    func testRunnerPrefersBundledEngineWhenPresent() throws {
        let root = try makeTemporaryDirectory()
        let engine = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: engine)
        }

        let bin = engine.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let redline = bin.appendingPathComponent("redline")
        try "#!/bin/sh\n".write(to: redline, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: redline.path)

        let runner = RedlineRunner(repoRoot: root, bundledEngineRoot: engine)

        XCTAssertEqual(runner.commandPrefix(), [redline.path, "check"])
        XCTAssertEqual(runner.workingDirectoryURL(), FileManager.default.homeDirectoryForCurrentUser)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
