import Foundation
import Observation
import SwiftUI

/// Plain-language re-check steps (app2.jsx CHECK_STEPS). Only the first stage uses AI.
struct CheckStep: Identifiable {
    let id = UUID()
    let lab: String
    let nt: String
}

let CHECK_STEPS: [CheckStep] = [
    CheckStep(lab: "Reading the document", nt: "page by page"),
    CheckStep(lab: "Pulling out the key terms", nt: "the only AI step"),
    CheckStep(lab: "Double-checking what it found", nt: "every value carries a quote"),
    CheckStep(lab: "Running the checks", nt: "exact rules, no guessing"),
]

/// A request to open a source lease PDF at a cited page (G6). Transient UI state only.
struct SourcePageRequest: Identifiable {
    let id = UUID()
    let url: URL
    let page: Int
}

struct PendingRunRetry {
    var source: RunSource
    var saveThread: Bool
}

/// Owns everything the three panes share: the library, the selected document, the
/// bidirectional report↔document sync, per-document review/notes, the re-check
/// animation, the live engine run, and the settings (the old design-host "Tweaks").
@MainActor
@Observable
final class Workspace {
    // top-level screen (home dashboard ↔ three-pane workspace)
    enum Screen { case home, workspace }
    var screen: Screen = .home

    // library
    var documents: [ReviewDoc]
    var groups: [DocGroup]
    var selectedDocID: String
    var query: String = ""

    // report ↔ document sync
    var selFindingID: String?
    var activeClause: String?
    var scrollTick: Int = 0

    // transient: a request to open the real source PDF at a cited page (G6)
    var sourcePageRequest: SourcePageRequest?

    // Inputs of the last failed run, so the error view's Retry can re-open the sheet pre-filled.
    // Transient: never persisted (mirrors sourcePageRequest).
    var pendingRetry: PendingRunRetry?

    // per-document review state, keyed "docID:findingID"
    var reviewed: [String: Bool] = [:]
    var notes: [String: String] = [:]

    // report-layout slide-over
    var docOpen: Bool = false

    // settings (was the floating Tweaks panel)
    var isDark: Bool = false { didSet { persistSettings() } }
    var accentHex: String = "#c8302b" { didSet { persistSettings() } }
    var layout: RLLayout = .split { didSet { persistSettings() } }
    var docSize: CGFloat = 16 { didSet { persistSettings() } }

    // AI provider config — was collected per-run in the modal; now set once here and
    // reused by every run and re-check. The run modal only reflects these read-only.
    var provider: LLMProvider = .codex { didSet { persistSettings() } }
    var model: String = LLMProvider.codex.defaultModel { didSet { persistSettings() } }
    var baseURL: String = LLMProvider.codex.defaultBaseURL { didSet { persistSettings() } }
    var apiKey: String = ""

    // engine run — single source of truth (replaces checking/checkStep/isRunning/runError)
    var run: RunPhase = .idle
    private var runTask: Task<Void, Never>?
    private var runProcess: Process?
    private var cancelRequested = false

    // View-compat shims so existing views keep compiling (HomeView/WorkspaceView/ContentView).
    var checking: Bool { run.isRunning }
    var checkStep: Int { run.step }
    var isRunning: Bool { run.isRunning }

    var showRunSheet: Bool = false
    var showSettingsPanel: Bool = false

    func openRunSheet() {
        guard !run.isRunning else {
            showSettingsPanel = false
            return
        }
        showSettingsPanel = false
        showRunSheet = true
    }

    private let runner: any RedlineRunning
    private var checkTask: Task<Void, Never>?
    private let storeURL: URL

    init(storeURL: URL = LibraryStore.defaultURL(), runner: (any RedlineRunning)? = nil) {
        self.storeURL = storeURL
        self.runner = runner ?? RedlineRunner(repoRoot: RedlineRunner.defaultRepoRoot())
        let storeExistedBeforeLoad = FileManager.default.fileExists(atPath: storeURL.path)
        // Restore the library if a snapshot exists; otherwise open to the first-run invite.
        if let snap = LibraryStore.load(from: storeURL) {
            documents = snap.documents
            groups = snap.groups
            selectedDocID = snap.selectedDocID
            reviewed = snap.reviewed
            notes = snap.notes
            sweepUnreferencedImportedSources()
        } else {
            documents = []
            groups = []
            selectedDocID = ""
            if !storeExistedBeforeLoad {
                sweepUnreferencedImportedSources()
            }
        }
        restoreSettings()
    }

    /// Pull in the bundled sample documents — the first-run "Load examples" affordance.
    func loadExamples() {
        documents = SampleData.documents
        groups = SampleData.groups
        if let first = documents.first {
            selectedDocID = first.id
            resetSelection(for: first)
        }
        persist()
    }

    /// Switch the persistent provider and reset its model / base-URL / key to defaults.
    func selectProvider(_ p: LLMProvider) {
        provider = p
        model = p.defaultModel
        baseURL = p.defaultBaseURL
        if p == .ollama || p == .codex { apiKey = "" }
    }

    // MARK: derived

    var theme: RLTheme { RLTheme(isDark: isDark, accent: Color(hex: accentHex), docSize: docSize) }

    var currentDoc: ReviewDoc? {
        documents.first { $0.id == selectedDocID } ?? documents.first
    }

    func doc(_ id: String) -> ReviewDoc? { documents.first { $0.id == id } }

    // MARK: selection + sync

    private func resetSelection(for doc: ReviewDoc) {
        let lead = doc.allFindings.first { $0.id == doc.verdict.lead } ?? doc.findings.first
        selFindingID = lead?.id
        activeClause = lead?.evidence.first?.clause
        // no scrollTick bump — the document shouldn't auto-jump on initial open
    }

    func selectDoc(_ id: String) {
        guard !run.isRunning else { return }
        guard let d = doc(id) else { return }
        checkTask?.cancel()
        run = .idle
        docOpen = false
        selectedDocID = id
        screen = .workspace
        resetSelection(for: d)
        persist()
    }

    /// Return to the home dashboard, stopping any in-flight re-check animation.
    func goHome() {
        guard !run.isRunning else { return }
        checkTask?.cancel()
        run = .idle
        docOpen = false
        screen = .home
    }

    /// Click a finding → open it and scroll the document to its first cited clause.
    func selectFinding(_ id: String?) {
        selFindingID = id
        guard let id, let doc = currentDoc,
              let f = doc.allFindings.first(where: { $0.id == id }) else { return }
        activeClause = f.evidence.first?.clause
        scrollTick += 1
    }

    /// Open the real source PDF at a cited page (G6). No-op-safe: callers only call this
    /// when the doc has a source PDF.
    func openSourcePage(_ url: URL, page: Int) {
        sourcePageRequest = SourcePageRequest(url: url, page: page)
    }

    /// Click a clause / evidence row → select the owning finding and scroll to the clause.
    func jumpClause(_ cid: String) {
        if let doc = currentDoc,
           let f = doc.allFindings.first(where: { $0.evidence.contains { $0.clause == cid } }) {
            selFindingID = f.id
        }
        activeClause = cid
        scrollTick += 1
        docOpen = true   // matters only in report layout; harmless elsewhere
    }

    // MARK: per-document review state

    private func key(_ fid: String) -> String { selectedDocID + ":" + fid }
    func isReviewed(_ fid: String) -> Bool { reviewed[key(fid)] ?? false }
    func toggleReviewed(_ fid: String) { reviewed[key(fid)] = !(reviewed[key(fid)] ?? false); persist() }
    func note(_ fid: String) -> String { notes[key(fid)] ?? "" }
    func setNote(_ fid: String, _ value: String) { notes[key(fid)] = value; persist() }

    func allErrorsCleared(_ doc: ReviewDoc) -> Bool {
        let problems = doc.findings.filter { $0.severity == .error }
        return !problems.isEmpty && problems.allSatisfy { reviewed[doc.id + ":" + $0.id] ?? false }
    }

    // MARK: re-check

    /// Re-check the current document. Engine-backed docs re-run the real pipeline;
    /// sample docs just play the animation (there's no PDF to re-read).
    func recheck() {
        guard !run.isRunning else { return }
        guard let doc = currentDoc, let source = doc.source else {
            playCheckingAnimation()
            return
        }
        var src = source
        src.apiKey = apiKey   // live key from Settings; persisted source.apiKey is "" after relaunch
        runTask = Task { await runEngine(source: src, replacingDocID: doc.id, persistThread: !src.thread.isEmpty) }
    }

    private func playCheckingAnimation() {
        checkTask?.cancel()
        run = .running(step: 0)
        checkTask = Task { [weak self] in
            let n = CHECK_STEPS.count
            for i in 1...n {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                self?.run = .running(step: i)
            }
            try? await Task.sleep(for: .milliseconds(480))
            if Task.isCancelled { return }
            self?.run = .idle
        }
    }

    // MARK: engine

    /// Start a run from the modal. Provider/model/key come from the persistent AI config
    /// (Settings), not the modal — the modal only supplies the document inputs.
    func startRun(leasePDF: URL, deal: DealContext, originalLeaseFilename: String? = nil) {
        guard !run.isRunning else { return }
        var source = RunSource(
            leasePDF: leasePDF, dealSheet: deal.dealSheet, context: deal.context,
            failOn: .error, provider: provider, model: model,
            baseURL: baseURL, apiKey: apiKey, thread: deal.thread)
        source.originalLeaseFilename = cleanOriginalLeaseFilename(originalLeaseFilename) ?? leasePDF.lastPathComponent
        discardPendingRetry(preserving: source)
        let preflight = RunPreflight.validate(
            leasePDF: leasePDF, dealSheet: deal.dealSheet,
            provider: provider, model: model, baseURL: baseURL, apiKey: apiKey)
        guard preflight.canRun else {
            pendingRetry = PendingRunRetry(source: source, saveThread: deal.saveThread)
            let message = preflight.message ?? "Redline could not start this check."
            run = .failed(RunFailure(cause: .badInput, guidance: message, raw: message))
            return
        }
        showRunSheet = false
        runTask = Task { await runEngine(source: source, replacingDocID: nil, persistThread: deal.saveThread) }
    }

    func cancelRunSheet() {
        discardPendingRetry()
        showRunSheet = false
    }

    func cancelRun() {
        cancelRequested = true
        runProcess?.terminate()
        runTask?.cancel()
        checkTask?.cancel()
        runProcess = nil
        showRunSheet = false
        run = .idle
    }

    /// Retry a failed run: dismiss the error and re-open the run sheet. `pendingRetry` stays set
    /// so RunSheet pre-fills the prior inputs on appear.
    func retryAfterFailure() {
        run = .idle
        openRunSheet()
    }

    /// Dismiss the error without retrying; drop the retained inputs.
    func dismissFailure() {
        discardPendingRetry()
        run = .idle
    }

    private func runEngine(source: RunSource, replacingDocID: String?, persistThread: Bool) async {
        cancelRequested = false
        pendingRetry = nil
        run = .running(step: 0)
        var retrySource = source

        let prepared: PreparedRunSource
        do {
            prepared = try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: persistThread)
            retrySource = prepared.runtime
            cleanupSourceFiles(from: source, preserving: prepared.runtime)
        } catch {
            run = .failed(RunFailure.map(error))
            pendingRetry = PendingRunRetry(source: source, saveThread: persistThread)
            return
        }

        // Advance the animation while the engine works (cap before the final step).
        let stepper = Task { [weak self] in
            let cap = CHECK_STEPS.count - 1
            for i in 1...cap {
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
                self?.run = .running(step: i)
            }
        }

        do {
            let report = try await runner.run(
                leasePDF: prepared.runtime.leasePDF,
                dealSheet: prepared.runtime.dealSheet,
                context: prepared.runtime.context,
                failOn: prepared.runtime.failOn,
                provider: prepared.runtime.provider,
                model: prepared.runtime.model,
                baseURL: prepared.runtime.baseURL,
                apiKey: prepared.runtime.apiKey,
                thread: prepared.runtime.thread,
                onLaunch: { [weak self] process in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.cancelRequested {
                            process.terminate()   // cancel beat the launch hop — kill it now
                        } else {
                            self.runProcess = process
                        }
                    }
                }
            )
            stepper.cancel()
            runProcess = nil
            run = .running(step: CHECK_STEPS.count)
            let id = replacingDocID ?? "run:\(UUID().uuidString.prefix(8))"
            var newDoc = ReportAdapter.makeDoc(from: report, source: prepared.persisted, id: String(id))
            if let replacingDocID,
               let existing = documents.first(where: { $0.id == replacingDocID }) {
                newDoc.name = existing.name
            }
            replaceOrAddDoc(newDoc)
            selectedDocID = newDoc.id
            resetSelection(for: newDoc)
            screen = .workspace   // a run started from Home lands in the workspace on its result
            try? await Task.sleep(for: .milliseconds(350))
            run = .idle
        } catch {
            stepper.cancel()
            runProcess = nil
            if error is CancellationError {
                cleanupSourceFiles(from: prepared.runtime)
                run = .idle
            } else if case RedlineRunError.cancelled = error {
                cleanupSourceFiles(from: prepared.runtime)
                run = .idle
            }
            else {
                pendingRetry = PendingRunRetry(source: retrySource, saveThread: persistThread)
                run = .failed(RunFailure.map(error))
            }
        }
    }

    private func replaceOrAddDoc(_ doc: ReviewDoc) {
        defer { persist() }
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
            return
        }
        documents.append(doc)
        if let gi = groups.firstIndex(where: { $0.id == "yours" }) {
            groups[gi].ids.append(doc.id)
        } else {
            groups.append(DocGroup(id: "yours", label: "Your documents", ids: [doc.id]))
        }
    }

    func deleteDoc(_ id: String) {
        guard !run.isRunning else { return }
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        let removed = documents[idx]
        documents.remove(at: idx)
        groups = groups.map { group in
            var group = group
            group.ids.removeAll { $0 == id }
            return group
        }
        reviewed = reviewed.filter { !$0.key.hasPrefix("\(id):") }
        notes = notes.filter { !$0.key.hasPrefix("\(id):") }

        if selectedDocID == id {
            if documents.isEmpty {
                selectedDocID = ""
                selFindingID = nil
                activeClause = nil
                screen = .home
                docOpen = false
            } else {
                let next = documents[min(idx, documents.count - 1)]
                selectedDocID = next.id
                resetSelection(for: next)
            }
        }
        cleanupSourceFiles(from: removed.source)
        persist()
    }

    func renameDoc(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].name = trimmed
        persist()
    }

    func replaceSourcePDF(for id: String, with url: URL) throws {
        guard !run.isRunning else { return }
        guard let idx = documents.firstIndex(where: { $0.id == id }),
              var source = documents[idx].source else { return }
        let oldSource = source
        source.leasePDF = try RunSourceFileStore.importLeasePDF(url, storeURL: storeURL)
        source.originalLeaseFilename = url.lastPathComponent
        source.apiKey = ""
        documents[idx].source = source
        documents[idx].name = url.deletingPathExtension().lastPathComponent
        cleanupSourceFiles(from: oldSource)
        persist()
    }

    private func discardPendingRetry(preserving preservedSource: RunSource? = nil) {
        cleanupSourceFiles(from: pendingRetry?.source, preserving: preservedSource)
        pendingRetry = nil
    }

    private func cleanupSourceFiles(from source: RunSource?, preserving preservedSource: RunSource? = nil) {
        guard let source else { return }
        var urls = [source.leasePDF]
        if let dealSheet = source.dealSheet { urls.append(dealSheet) }
        let preservedPaths = Set(sourceURLs(from: preservedSource).map { $0.standardizedFileURL.path })

        for url in urls {
            let isImportedSource = RunSourceFileStore.isImportedSource(url, storeURL: storeURL)
            let isDroppedTemp = RunSheetFileIntake.isTemporaryDroppedPDF(url)
            guard isImportedSource || isDroppedTemp else { continue }

            let path = url.standardizedFileURL.path
            let stillReferenced = documents.contains { doc in
                guard let source = doc.source else { return false }
                if source.leasePDF.standardizedFileURL.path == path { return true }
                if source.dealSheet?.standardizedFileURL.path == path { return true }
                return false
            } || preservedPaths.contains(path)
            if !stillReferenced {
                if isDroppedTemp {
                    RunSheetFileIntake.removeTemporaryDroppedPDF(url)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func sweepUnreferencedImportedSources() {
        let imports = RunSourceFileStore.importsDirectory(forStoreURL: storeURL)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: imports,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        let referencedPaths = Set(documents.flatMap { sourceURLs(from: $0.source) }
            .filter { RunSourceFileStore.isImportedSource($0, storeURL: storeURL) }
            .map { $0.standardizedFileURL.path })

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            let path = url.standardizedFileURL.path
            if !referencedPaths.contains(path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func sourceURLs(from source: RunSource?) -> [URL] {
        guard let source else { return [] }
        var urls = [source.leasePDF]
        if let dealSheet = source.dealSheet { urls.append(dealSheet) }
        return urls
    }

    private func cleanOriginalLeaseFilename(_ filename: String?) -> String? {
        let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: persistence

    private func persist() {
        let snap = LibrarySnapshot(
            documents: documents, groups: groups,
            selectedDocID: selectedDocID, reviewed: reviewed, notes: notes)
        try? LibraryStore.save(snap, to: storeURL)
    }

    private func restoreSettings() {
        let d = UserDefaults.standard
        isDark = d.bool(forKey: "rl.isDark")
        if let hex = d.string(forKey: "rl.accentHex") { accentHex = hex }
        if let raw = d.string(forKey: "rl.layout"), let l = RLLayout(rawValue: raw) { layout = l }
        if d.object(forKey: "rl.docSize") != nil { docSize = CGFloat(d.double(forKey: "rl.docSize")) }
        if let raw = d.string(forKey: "rl.provider"), let p = LLMProvider(rawValue: raw) {
            provider = p; model = d.string(forKey: "rl.model") ?? p.defaultModel
            baseURL = d.string(forKey: "rl.baseURL") ?? p.defaultBaseURL
        }
        // apiKey is intentionally NOT restored — never persisted.
    }

    private func persistSettings() {
        let d = UserDefaults.standard
        d.set(isDark, forKey: "rl.isDark"); d.set(accentHex, forKey: "rl.accentHex")
        d.set(layout.rawValue, forKey: "rl.layout"); d.set(Double(docSize), forKey: "rl.docSize")
        d.set(provider.rawValue, forKey: "rl.provider"); d.set(model, forKey: "rl.model")
        d.set(baseURL, forKey: "rl.baseURL")
    }
}
