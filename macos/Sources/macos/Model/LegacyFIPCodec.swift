import Foundation

enum LegacyFIPCodec {
    static func load(text: String, sourcePath: String? = nil) throws -> FrieveDocument {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var metadata: [String: String] = [:]
        var orderedCardIDs: [Int] = []
        var cardLabels: [FrieveLabel] = []
        var linkLabels: [FrieveLabel] = []
        var links: [FrieveLink] = []
        var cards: [FrieveCard] = []
        var focusedCardID: Int?
        var section = ""
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmed
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line
                index += 1
                continue
            }

            switch section {
            case "[Global]":
                if let (key, value) = parseColonlessKeyValue(lines[index]) {
                    metadata[key] = value
                }
                index += 1

            case "[Card]":
                if let (key, value) = parseColonlessKeyValue(lines[index]) {
                    if key == "CardID" {
                        focusedCardID = Int(value)
                    } else if Int(key) != nil, let cardID = Int(value) {
                        orderedCardIDs.append(cardID)
                    }
                }
                index += 1

            case "[Link]":
                if let (key, value) = parseColonlessKeyValue(lines[index]), Int(key) != nil {
                    links.append(parseLegacyLink(value))
                }
                index += 1

            case "[Label]":
                if let (key, value) = parseColonlessKeyValue(lines[index]), Int(key) != nil {
                    cardLabels.append(parseLegacyLabel(id: Int(key) ?? 0, encoded: value))
                }
                index += 1

            case "[LinkLabel]":
                if let (key, value) = parseColonlessKeyValue(lines[index]), Int(key) != nil {
                    linkLabels.append(parseLegacyLabel(id: Int(key) ?? 0, encoded: value))
                }
                index += 1

            case "[CardData]":
                if let cardID = Int(line) {
                    index += 1
                    var fields: [String: String] = [:]
                    while index < lines.count, lines[index].trimmed != "-" {
                        if let (key, value) = parseColonKeyValue(lines[index]) {
                            fields[key] = value
                        }
                        index += 1
                    }
                    if index < lines.count, lines[index].trimmed == "-" {
                        index += 1
                    }
                    var bodyLines: [String] = []
                    while index < lines.count {
                        let current = lines[index].trimmed
                        let next = index + 1 < lines.count ? lines[index + 1] : ""
                        if Int(current) != nil, next.hasPrefix("Title:") {
                            break
                        }
                        bodyLines.append(lines[index])
                        index += 1
                    }
                    cards.append(
                        FrieveCard(
                            id: cardID,
                            title: fields["Title"] ?? "Card \(cardID)",
                            bodyText: bodyLines.joined(separator: "\n"),
                            drawingEncoded: fields["Drawing"] ?? "",
                            visible: (Int(fields["Visible"] ?? "1") ?? 1) != 0,
                            shape: Int(fields["Shape"] ?? "2") ?? 2,
                            size: Int(fields["Size"] ?? "100") ?? 100,
                            isTop: (Int(fields["Top"] ?? "0") ?? 0) != 0,
                            isFixed: (Int(fields["Fixed"] ?? "0") ?? 0) != 0,
                            isFolded: (Int(fields["Fold"] ?? "0") ?? 0) != 0,
                            position: FrievePoint(
                                x: Double(fields["X"] ?? "0.5") ?? 0.5,
                                y: Double(fields["Y"] ?? "0.5") ?? 0.5
                            ),
                            created: fields["Created"] ?? "",
                            updated: fields["Updated"] ?? "",
                            viewed: fields["Viewed"] ?? "",
                            labelIDs: commaSeparatedInts(fields["Label"]),
                            score: Double(fields["Score"] ?? "0") ?? 0,
                            imagePath: nil,
                            videoPath: nil
                        )
                    )
                } else {
                    index += 1
                }

            default:
                index += 1
            }
        }

        if !orderedCardIDs.isEmpty {
            let ordering = orderedCardIDs.enumerated().reduce(into: [Int: Int]()) { partial, entry in
                partial[entry.element] = partial[entry.element] ?? entry.offset
            }
            cards.sort { (ordering[$0.id] ?? .max) < (ordering[$1.id] ?? .max) }
        }

        var document = FrieveDocument(
            title: cards.first?.title ?? "Frieve Editor Help",
            metadata: metadata,
            focusedCardID: focusedCardID,
            cards: cards,
            links: links,
            cardLabels: cardLabels,
            linkLabels: linkLabels,
            sourcePath: sourcePath
        )
        document.ensureFocusedCard()
        return document
    }

    private static func parseColonlessKeyValue(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        return (
            String(line[..<separator]).trimmed,
            String(line[line.index(after: separator)...])
        )
    }

    private static func parseColonKeyValue(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        return (
            String(line[..<separator]).trimmed,
            String(line[line.index(after: separator)...])
        )
    }

    private static func parseLegacyLabel(id: Int, encoded: String) -> FrieveLabel {
        FrieveLabel(
            id: id + 1,
            name: tokenValue(in: encoded, prefix: "Na") ?? "Label \(id + 1)",
            color: Int(tokenValue(in: encoded, prefix: "Co") ?? "0") ?? 0,
            enabled: (Int(tokenValue(in: encoded, prefix: "En") ?? "1") ?? 1) != 0,
            show: (Int(tokenValue(in: encoded, prefix: "Sh") ?? "1") ?? 1) != 0,
            hide: (Int(tokenValue(in: encoded, prefix: "Hi") ?? "0") ?? 0) != 0,
            fold: (Int(tokenValue(in: encoded, prefix: "Fo") ?? "0") ?? 0) != 0,
            size: Int(tokenValue(in: encoded, prefix: "Si") ?? "100") ?? 100
        )
    }

    private static func parseLegacyLink(_ encoded: String) -> FrieveLink {
        let labels = encoded
            .split(separator: ",")
            .compactMap { token -> Int? in
                let string = String(token)
                guard string.hasPrefix("La") else { return nil }
                return (Int(string.dropFirst(2)) ?? 0) + 1
            }
        return FrieveLink(
            fromCardID: Int(tokenValue(in: encoded, prefix: "Fr") ?? "0") ?? 0,
            toCardID: Int(tokenValue(in: encoded, prefix: "De") ?? "0") ?? 0,
            directionVisible: (Int(tokenValue(in: encoded, prefix: "Di") ?? "1") ?? 1) != 0,
            shape: Int(tokenValue(in: encoded, prefix: "Sh") ?? "5") ?? 5,
            labelIDs: labels,
            name: tokenValue(in: encoded, prefix: "Na") ?? ""
        )
    }

    private static func tokenValue(in encoded: String, prefix: String) -> String? {
        encoded.split(separator: ",").compactMap { token -> String? in
            let string = String(token)
            guard string.hasPrefix(prefix) else { return nil }
            return String(string.dropFirst(prefix.count))
        }.first
    }

    private static func commaSeparatedInts(_ value: String?) -> [Int] {
        guard let value else { return [] }
        return value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
