import Foundation

/// Turns a real engine run (`CheckReport` from `redline check --json`) into the rich
/// `ReviewDoc` the v2 workspace renders. The engine has no clause structure, so we
/// synthesize a source document from the cited evidence (one clause per quote, grouped
/// by page) — enough for the synced highlight to land on what the engine actually cited.
enum ReportAdapter {

    static func severity(_ raw: String) -> Severity {
        switch raw.uppercased() {
        case "ERROR": .error
        case "WARN": .warn
        case "INFO": .info
        case "COULD_NOT_VERIFY": .verify
        case "ADVISORY": .advisory
        case "SKIP": .skip
        default: .pass
        }
    }

    static func makeDoc(from report: CheckReport, source: RunSource, id: String) -> ReviewDoc {
        // Build the synthetic document from every cited quote, grouped by page.
        var pages: [Int: [Clause]] = [:]
        var clauseKeyToID: [String: String] = [:]   // "page|quote" → clause id
        var counter = 0

        func clauseID(forQuote quote: String, page: Int, ruleTitle: String) -> String {
            let key = "\(page)|\(quote)"
            if let existing = clauseKeyToID[key] { return existing }
            counter += 1
            let cid = "ev-\(page)-\(counter)"
            clauseKeyToID[key] = cid
            pages[page, default: []].append(
                Clause(id: cid, num: "p\(page)", title: ruleTitle, text: quote)
            )
            return cid
        }

        func mapFinding(_ f: Finding, index: Int) -> ReviewFinding {
            let sev = severity(f.severity)
            let page0 = f.evidence.first?.page ?? 1
            let evidence: [ReviewEvidence] = f.evidence.compactMap { ev in
                guard let quote = ev.quote, !quote.isEmpty else { return nil }
                let cid = clauseID(forQuote: quote, page: ev.page ?? page0, ruleTitle: f.title)
                return ReviewEvidence(clause: cid, quote: quote)
            }
            return ReviewFinding(
                id: "\(f.ruleID)#\(index)",
                rule: f.ruleID,
                severity: sev,
                title: f.title,
                detail: f.detail,
                plain: f.title,            // engine has no plain-language line — fall back to the title
                expected: f.expected,
                actual: f.actual,
                evidence: evidence
            )
        }

        let deterministic = dedupedFindings(report.deterministicFindings + report.couldNotVerify)
        let findings = deterministic.enumerated().map { mapFinding($1, index: $0) }
        let advisory = report.advisoryFindings.enumerated().map { mapFinding($1, index: 1000 + $0) }

        let document: [DocPage] = pages.keys.sorted().map { page in
            DocPage(page: page, heading: "Page \(page)", clauses: pages[page] ?? [])
        }

        let facts = keyTerms(from: report.factsSummary)
        let dealTerms = (report.dealTerms ?? []).map {
            DealTerm(label: $0.label, expected: $0.expected, actual: $0.actual,
                     verified: $0.verified, source: $0.source)
        }
        let errorCount = findings.filter { $0.severity == .error }.count
        let warnCount = findings.filter { $0.severity == .warn || $0.severity == .verify }.count
        let lead = findings.first(where: { $0.severity == .error })?.id ?? findings.first?.id ?? ""

        let sub: String
        if errorCount > 0 {
            sub = "Each issue cites a clause you can verify against the source document."
        } else if warnCount > 0 {
            sub = "A couple of items are worth a look — none of them block approval."
        } else {
            sub = "Every deterministic check ran clean."
        }

        let pageCount = report.factsSummary?.pageCount ?? (pages.keys.max() ?? 1)
        let profileName = report.profile?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewKind = ((profileName?.isEmpty == false ? profileName : nil) ?? "General lease") + " review"

        return ReviewDoc(
            id: id,
            name: documentName(from: source, fallback: report.factsSummary?.sourceFile),
            kind: reviewKind,
            type: "lease",
            party: source.dealSheet != nil ? "Compared with term sheet" : "Uploaded PDF",
            pages: pageCount,
            deal: !dealTerms.isEmpty || source.dealSheet != nil,
            verdict: Verdict(
                level: (report.exitCode != 0 || errorCount > 0) ? "error" : "pass",
                headline: errorCount > 0 ? "Needs review" : "Clears all checks",
                lead: lead,
                sub: sub
            ),
            facts: facts,
            findings: findings,
            advisory: advisory,
            dealTerms: dealTerms,
            document: document,
            source: source
        )
    }

    // MARK: helpers

    private static func dedupedFindings(_ findings: [Finding]) -> [Finding] {
        var seen = Set<String>()
        return findings.filter { finding in
            let evidenceKey = finding.evidence.map {
                "\($0.page.map(String.init) ?? ""):\($0.quote ?? "")"
            }.joined(separator: "|")
            let key = [
                finding.ruleID,
                finding.severity,
                finding.title,
                finding.detail,
                finding.expected ?? "",
                finding.actual ?? "",
                evidenceKey,
            ].joined(separator: "\u{1f}")
            return seen.insert(key).inserted
        }
    }

    private static func documentName(from source: RunSource, fallback: String?) -> String {
        if let filename = source.originalLeaseFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !filename.isEmpty {
            return (filename as NSString).deletingPathExtension
        }
        let stem = source.leasePDF.deletingPathExtension().lastPathComponent
        if !stem.isEmpty { return stem }
        if let fallback, !fallback.isEmpty {
            return (fallback as NSString).deletingPathExtension
        }
        return "Document"
    }

    private static func keyTerms(from facts: FactsSummary?) -> [KeyTerm] {
        guard let facts else { return [] }
        var terms: [KeyTerm] = []
        if let v = facts.statedTotalRent { terms.append(KeyTerm(k: "Stated total rent", v: v)) }
        if let v = facts.rentBasis {
            terms.append(KeyTerm(k: "Rent basis", v: prettyBasis(v), flag: v == "per_face"))
        }
        if let v = facts.perFaceRent { terms.append(KeyTerm(k: "Per-face rent", v: v)) }
        if let v = facts.numDisplayFaces { terms.append(KeyTerm(k: "Display faces", v: String(v))) }
        if let v = facts.baseTermYears { terms.append(KeyTerm(k: "Base term", v: "\(v) yr")) }
        if let v = facts.securityDeposit { terms.append(KeyTerm(k: "Security deposit", v: v)) }
        if let v = facts.defaultCurePeriodDays { terms.append(KeyTerm(k: "Default cure", v: "\(v) days")) }
        if let v = facts.renewalNoticeDeadlineDays {
            terms.append(KeyTerm(k: "Renewal notice", v: "\(v) days"))
        }
        if let v = facts.permittedUse { terms.append(KeyTerm(k: "Permitted use", v: v)) }
        if let v = facts.pageCount { terms.append(KeyTerm(k: "Pages", v: String(v))) }
        return terms
    }

    private static func prettyBasis(_ raw: String) -> String {
        switch raw {
        case "per_face": "per display face"
        case "total": "total"
        default: raw
        }
    }
}
