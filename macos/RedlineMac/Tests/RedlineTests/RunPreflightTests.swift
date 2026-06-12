import XCTest
@testable import Redline

final class RunPreflightTests: XCTestCase {
    func testRequiresLeasePDFBeforeRunCanStart() {
        let result = RunPreflight.validate(
            leasePDF: nil, dealSheet: nil,
            provider: .codex, model: "", baseURL: "", apiKey: "",
            environment: [:])

        XCTAssertFalse(result.canRun)
        XCTAssertEqual(result.message, "Choose a lease PDF.")
    }

    func testRejectsNonPDFLeaseBeforeLaunchingEngine() {
        let result = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.txt"), dealSheet: nil,
            provider: .codex, model: "", baseURL: "", apiKey: "",
            environment: [:])

        XCTAssertFalse(result.canRun)
        XCTAssertEqual(result.message, "Use a PDF lease.")
    }

    func testRejectsNonYAMLDealSheetBeforeLaunchingEngine() {
        let result = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"),
            dealSheet: URL(fileURLWithPath: "/tmp/deal.pdf"),
            provider: .codex, model: "", baseURL: "", apiKey: "",
            environment: [:])

        XCTAssertFalse(result.canRun)
        XCTAssertEqual(result.message, "Deal sheet must be a .yaml or .yml file.")
    }

    func testOpenAIRequiresModelAndAPIKey() {
        let noModel = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .openai, model: "", baseURL: "", apiKey: "sk-test",
            environment: [:])
        let noKey = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .openai, model: "gpt-4.1", baseURL: "", apiKey: "",
            environment: [:])
        let valid = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .openai, model: "gpt-4.1", baseURL: "", apiKey: "sk-test",
            environment: [:])

        XCTAssertFalse(noModel.canRun)
        XCTAssertEqual(noModel.message, "OpenAI runs need a model.")
        XCTAssertFalse(noKey.canRun)
        XCTAssertEqual(noKey.message, "OpenAI runs need an API key.")
        XCTAssertTrue(valid.canRun)
        XCTAssertNil(valid.message)
    }

    func testAnthropicRequiresModelAndAPIKey() {
        let noModel = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .anthropic, model: "", baseURL: "", apiKey: "sk-ant-test",
            environment: [:])
        let noKey = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .anthropic, model: "claude-sonnet-4-5", baseURL: "", apiKey: "",
            environment: [:])

        XCTAssertFalse(noModel.canRun)
        XCTAssertEqual(noModel.message, "Anthropic runs need a model.")
        XCTAssertFalse(noKey.canRun)
        XCTAssertEqual(noKey.message, "Anthropic runs need an API key.")
    }

    func testOllamaUsesDefaultsWhenFieldsAreBlank() {
        let result = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .ollama, model: "", baseURL: "", apiKey: "",
            environment: [:])

        XCTAssertTrue(result.canRun)
        XCTAssertNil(result.message)
    }

    func testOpenAIPreflightHonorsEnvironmentFallbacks() {
        let result = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .openai, model: "", baseURL: "", apiKey: "",
            environment: ["REDLINE_OPENAI_MODEL": "gpt-env", "OPENAI_API_KEY": "sk-env"])

        XCTAssertTrue(result.canRun)
        XCTAssertNil(result.message)
    }

    func testAnthropicPreflightHonorsGenericEnvironmentFallbacks() {
        let result = RunPreflight.validate(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"), dealSheet: nil,
            provider: .anthropic, model: "", baseURL: "", apiKey: "",
            environment: ["REDLINE_MODEL": "claude-env", "REDLINE_API_KEY": "sk-env"])

        XCTAssertTrue(result.canRun)
        XCTAssertNil(result.message)
    }
}
