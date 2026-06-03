struct DocListSection: Identifiable {
    let id: String
    var label: String
    var documents: [ReviewDoc]
}

func docListSections(
    documents: [ReviewDoc],
    groups: [DocGroup],
    fallbackLabel: String = "Your documents"
) -> [DocListSection] {
    var docsByID: [String: ReviewDoc] = [:]
    for doc in documents {
        docsByID[doc.id] = doc
    }

    var sections: [DocListSection] = []
    var groupedIDs = Set<String>()

    for group in groups {
        var seenInGroup = Set<String>()
        var items: [ReviewDoc] = []

        for id in group.ids {
            groupedIDs.insert(id)
            guard !seenInGroup.contains(id), let doc = docsByID[id] else { continue }
            seenInGroup.insert(id)
            items.append(doc)
        }

        if !items.isEmpty {
            sections.append(DocListSection(id: group.id, label: group.label, documents: items))
        }
    }

    let ungrouped = documents.filter { !groupedIDs.contains($0.id) }
    if !ungrouped.isEmpty {
        sections.append(DocListSection(
            id: "__redline_ungrouped_documents__",
            label: fallbackLabel,
            documents: ungrouped
        ))
    }

    return sections
}
