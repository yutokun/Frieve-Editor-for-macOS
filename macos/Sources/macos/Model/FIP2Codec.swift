import Foundation

enum FIP2Codec {
    static func load(data: Data, sourcePath: String? = nil) throws -> FrieveDocument {
        let text = String(decoding: data, as: UTF8.self)
        return try load(text: text, sourcePath: sourcePath)
    }

    static func load(text: String, sourcePath: String? = nil) throws -> FrieveDocument {
        let lines = normalizedLines(from: text)
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmed.isEmpty }) else {
            throw FrieveFileError.invalidMagicLine
        }
        guard lines[firstNonEmptyIndex].trimmed == "FIP2/1" else {
            throw FrieveFileError.invalidMagicLine
        }

        var metadata: [String: String] = [:]
        var cardLabels: [FrieveLabel] = []
        var linkLabels: [FrieveLabel] = []
        var links: [FrieveLink] = []
        var cards: [FrieveCard] = []
        var focusedCardID: Int?
        var index = firstNonEmptyIndex + 1

        while index < lines.count {
            let line = lines[index].trimmed
            if line.isEmpty {
                index += 1
                continue
            }

            switch line {
            case "[Global]":
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    let trimmed = candidate.trimmed
                    if trimmed.hasPrefix("[[") || (trimmed.hasPrefix("[") && trimmed != "[Global]") {
                        break
                    }
                    if let (key, value) = parseKeyValue(candidate) {
                        metadata[key] = value
                    }
                    index += 1
                }

            case let section where section.hasPrefix("[[LABELS type="):
                let labelType = section.contains("type=1") ? 1 : 0
                index += 1
                var parsedLabels: [FrieveLabel] = []
                while index < lines.count {
                    let trimmed = lines[index].trimmed
                    if trimmed == "[[END:LABELS]]" {
                        index += 1
                        break
                    }
                    guard trimmed == "[[LABEL]]" else {
                        throw FrieveFileError.malformedSection("LABELS")
                    }
                    index += 1
                    var labelFields: [String: String] = [:]
                    while index < lines.count {
                        let current = lines[index].trimmed
                        if current == "[[END:LABEL]]" {
                            index += 1
                            break
                        }
                        if let (key, value) = parseKeyValue(lines[index]) {
                            labelFields[key] = value
                        }
                        index += 1
                    }
                    parsedLabels.append(
                        FrieveLabel(
                            id: Int(labelFields["id"] ?? "0") ?? 0,
                            name: labelFields["name"] ?? "",
                            color: Int(labelFields["color"] ?? "0") ?? 0,
                            enabled: (Int(labelFields["enabled"] ?? "1") ?? 1) != 0,
                            show: (Int(labelFields["show"] ?? "1") ?? 1) != 0,
                            hide: (Int(labelFields["hide"] ?? "0") ?? 0) != 0,
                            fold: (Int(labelFields["fold"] ?? "0") ?? 0) != 0,
                            size: Int(labelFields["size"] ?? "100") ?? 100
                        )
                    )
                }
                if labelType == 0 {
                    cardLabels = parsedLabels
                } else {
                    linkLabels = parsedLabels
                }

            case "[[LINKS]]":
                index += 1
                while index < lines.count {
                    let trimmed = lines[index].trimmed
                    if trimmed == "[[END:LINKS]]" {
                        index += 1
                        break
                    }
                    guard trimmed == "[[LINK]]" else {
                        throw FrieveFileError.malformedSection("LINKS")
                    }
                    index += 1
                    var fields: [String: String] = [:]
                    while index < lines.count {
                        let current = lines[index].trimmed
                        if current == "[[END:LINK]]" {
                            index += 1
                            break
                        }
                        if let (key, value) = parseKeyValue(lines[index]) {
                            fields[key] = value
                        }
                        index += 1
                    }
                    links.append(
                        FrieveLink(
                            fromCardID: Int(fields["from"] ?? "0") ?? 0,
                            toCardID: Int(fields["to"] ?? "0") ?? 0,
                            directionVisible: (Int(fields["directionVisible"] ?? "1") ?? 1) != 0,
                            shape: Int(fields["shape"] ?? "5") ?? 5,
                            labelIDs: commaSeparatedInts(fields["labels"]),
                            name: fields["name"] ?? ""
                        )
                    )
                }

            case let section where section.hasPrefix("[[CARDS"):
                focusedCardID = Int(value(in: section, key: "focus") ?? "")
                index += 1
                while index < lines.count {
                    let trimmed = lines[index].trimmed
                    if trimmed == "[[END:CARDS]]" {
                        index += 1
                        break
                    }
                    guard trimmed.hasPrefix("[[CARD id=") else {
                        throw FrieveFileError.malformedSection("CARDS")
                    }
                    let cardID = Int(value(in: trimmed, key: "id") ?? "0") ?? 0
                    index += 1
                    var fields: [String: String] = [:]
                    var bodyLines: [String] = []
                    while index < lines.count {
                        let currentLine = lines[index]
                        let current = currentLine.trimmed
                        if current == "[[END:CARD]]" {
                            index += 1
                            break
                        }
                        if current.hasPrefix("<!--BODY token=") {
                            let token = value(in: current, key: "token") ?? ""
                            index += 1
                            while index < lines.count {
                                let bodyCandidate = lines[index]
                                if bodyCandidate.trimmed == "<!--END_BODY token=\(token)-->" {
                                    index += 1
                                    break
                                }
                                bodyLines.append(bodyCandidate)
                                index += 1
                            }
                            continue
                        }
                        if let (key, value) = parseKeyValue(currentLine) {
                            fields[key] = value
                        }
                        index += 1
                    }

                    cards.append(
                        FrieveCard(
                            id: cardID,
                            title: fields["title"] ?? "Card \(cardID)",
                            bodyText: bodyLines.joined(separator: "\n"),
                            drawingEncoded: fields["drawing"] ?? "",
                            visible: (Int(fields["visible"] ?? "1") ?? 1) != 0,
                            shape: Int(fields["shape"] ?? "2") ?? 2,
                            size: Int(fields["size"] ?? "100") ?? 100,
                            isTop: (Int(fields["top"] ?? "0") ?? 0) != 0,
                            isFixed: (Int(fields["fixed"] ?? "0") ?? 0) != 0,
                            isFolded: (Int(fields["fold"] ?? "0") ?? 0) != 0,
                            position: FrievePoint(
                                x: Double(fields["x"] ?? "0.5") ?? 0.5,
                                y: Double(fields["y"] ?? "0.5") ?? 0.5
                            ),
                            created: fields["created"] ?? "",
                            updated: fields["updated"] ?? "",
                            viewed: fields["viewed"] ?? "",
                            labelIDs: commaSeparatedInts(fields["labelList"]),
                            score: Double(fields["score"] ?? "0") ?? 0,
                            imagePath: fields["image"],
                            videoPath: fields["video"]
                        )
                    )
                }

            default:
                index += 1
            }
        }

        var document = FrieveDocument(
            title: metadata["Title"] ?? cards.first?.title ?? "Frieve Editor",
            metadata: metadata,
            focusedCardID: focusedCardID,
            cards: cards,
            links: links,
            cardLabels: cardLabels.sorted { $0.id < $1.id },
            linkLabels: linkLabels.sorted { $0.id < $1.id },
            sourcePath: sourcePath
        )
        document.metadata["Title"] = document.title
        document.ensureFocusedCard()
        return document
    }

    static func save(document: FrieveDocument) -> String {
        var lines: [String] = []
        var metadata = document.metadata
        metadata["Title"] = document.title
        lines.append("FIP2/1")
        lines.append("This is a UTF-8 text file in Frieve Editor's fip2 format.")
        lines.append("")
        lines.append("[Global]")
        for key in metadata.keys.sorted() {
            guard key != "Title" else { continue }
            lines.append("\(key)=\(metadata[key] ?? "")")
        }
        lines.append("Title=\(document.title)")
        lines.append("")

        func appendLabels(_ labels: [FrieveLabel], type: Int) {
            lines.append("[[LABELS type=\(type)]]")
            for label in labels.sorted(by: { $0.id < $1.id }) {
                lines.append("[[LABEL]]")
                lines.append("id=\(label.id)")
                lines.append("name=\(label.name)")
                lines.append("color=\(label.color)")
                lines.append("enabled=\(label.enabled ? 1 : 0)")
                lines.append("show=\(label.show ? 1 : 0)")
                lines.append("hide=\(label.hide ? 1 : 0)")
                lines.append("fold=\(label.fold ? 1 : 0)")
                lines.append("size=\(label.size)")
                lines.append("[[END:LABEL]]")
            }
            lines.append("[[END:LABELS]]")
            lines.append("")
        }

        appendLabels(document.cardLabels, type: 0)
        appendLabels(document.linkLabels, type: 1)

        lines.append("[[LINKS]]")
        for link in document.links {
            lines.append("[[LINK]]")
            lines.append("from=\(link.fromCardID)")
            lines.append("to=\(link.toCardID)")
            lines.append("directionVisible=\(link.directionVisible ? 1 : 0)")
            lines.append("shape=\(link.shape)")
            lines.append("labels=\(link.labelIDs.map(String.init).joined(separator: ","))")
            lines.append("name=\(link.name)")
            lines.append("[[END:LINK]]")
        }
        lines.append("[[END:LINKS]]")
        lines.append("")

        lines.append("[[CARDS focus=\(document.focusedCardID ?? document.cards.first?.id ?? 0)]]")
        for card in document.cards.sorted(by: { $0.id < $1.id }) {
            let token = makeBodyToken(for: card)
            lines.append("[[CARD id=\(card.id)]]")
            lines.append("title=\(card.title)")
            lines.append("visible=\(card.visible ? 1 : 0)")
            lines.append("shape=\(card.shape)")
            lines.append("size=\(card.size)")
            lines.append("top=\(card.isTop ? 1 : 0)")
            lines.append("fixed=\(card.isFixed ? 1 : 0)")
            lines.append("fold=\(card.isFolded ? 1 : 0)")
            lines.append("x=\(card.position.x)")
            lines.append("y=\(card.position.y)")
            lines.append("created=\(card.created)")
            lines.append("updated=\(card.updated)")
            lines.append("viewed=\(card.viewed)")
            lines.append("score=\(card.score)")
            lines.append("labelList=\(card.labelIDs.map(String.init).joined(separator: ","))")
            lines.append("drawing=\(card.drawingEncoded)")
            if let imagePath = card.imagePath {
                lines.append("image=\(imagePath)")
            }
            if let videoPath = card.videoPath {
                lines.append("video=\(videoPath)")
            }
            lines.append("<!--BODY token=\(token)-->")
            lines.append(contentsOf: card.bodyLines)
            lines.append("<!--END_BODY token=\(token)-->")
            lines.append("[[END:CARD]]")
        }
        lines.append("[[END:CARDS]]")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func normalizedLines(from text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func parseKeyValue(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<separator]).trimmed
        let value = String(line[line.index(after: separator)...])
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private static func commaSeparatedInts(_ value: String?) -> [Int] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func value(in tokenLine: String, key: String) -> String? {
        guard let range = tokenLine.range(of: "\(key)=") else { return nil }
        let suffix = tokenLine[range.upperBound...]
        if let end = suffix.firstIndex(of: "]") {
            return String(suffix[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "]>"))
        }
        if let end = suffix.firstIndex(of: "-") {
            return String(suffix[..<end]).trimmed
        }
        return String(suffix).trimmingCharacters(in: CharacterSet(charactersIn: "]>"))
    }

    private static func makeBodyToken(for card: FrieveCard) -> String {
        var seed = "\(card.id):\(card.title):\(card.bodyText)"
        var attempt = 0
        while true {
            let value = stableHex16(for: seed)
            let start = "<!--BODY token=\(value)-->"
            let end = "<!--END_BODY token=\(value)-->"
            if !card.bodyLines.contains(where: { $0.trimmed == start || $0.trimmed == end }) {
                return value
            }
            attempt += 1
            seed += "#\(attempt)"
        }
    }

    private static func stableHex16(for string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llX", hash)
    }
}
