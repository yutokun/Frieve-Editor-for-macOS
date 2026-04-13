import Foundation

struct FrievePoint: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = FrievePoint(x: 0.5, y: 0.5)
}

enum WorkspaceTab: String, CaseIterable, Identifiable, Codable {
    case browser = "Browser"
    case editor = "Editor"
    case drawing = "Drawing"
    case statistics = "Statistics"

    var id: String { rawValue }
}

struct FrieveLabel: Identifiable, Codable, Hashable {
    var id: Int
    var name: String
    var color: Int
    var enabled: Bool
    var show: Bool
    var hide: Bool
    var fold: Bool
    var size: Int
}

struct FrieveLink: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fromCardID: Int
    var toCardID: Int
    var directionVisible: Bool
    var shape: Int
    var labelIDs: [Int]
    var name: String
}

struct FrieveCard: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var bodyText: String
    var drawingEncoded: String
    var visible: Bool
    var shape: Int
    var size: Int
    var isTop: Bool
    var isFixed: Bool
    var isFolded: Bool
    var position: FrievePoint
    var created: String
    var updated: String
    var viewed: String
    var labelIDs: [Int]
    var score: Double
    var imagePath: String?
    var videoPath: String?

    var bodyLines: [String] {
        bodyText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var summary: String {
        let compact = bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "No body text" : String(compact.prefix(96))
    }

    var hasMedia: Bool {
        !(imagePath?.trimmed.isEmpty ?? true) || !(videoPath?.trimmed.isEmpty ?? true)
    }

    var primaryMediaPath: String? {
        if let imagePath, !imagePath.trimmed.isEmpty {
            return imagePath
        }
        if let videoPath, !videoPath.trimmed.isEmpty {
            return videoPath
        }
        return nil
    }

    var hasDrawingPreview: Bool {
        !drawingEncoded.trimmed.isEmpty && !drawingPreviewItems().isEmpty
    }

    var normalizedShapeIndex: Int {
        ((shape % 6) + 6) % 6
    }

    var shapeName: String {
        switch normalizedShapeIndex {
        case 0: "Rect"
        case 1: "Capsule"
        case 2: "Round"
        case 3: "Diamond"
        case 4: "Hexagon"
        default: "Note"
        }
    }

    var shapeSymbolName: String {
        switch normalizedShapeIndex {
        case 0: "rectangle.roundedtop"
        case 1: "capsule.portrait"
        case 2: "square.roundedbottom"
        case 3: "diamond"
        case 4: "hexagon"
        default: "note.text"
        }
    }

    var mediaBadgeText: String {
        if let imagePath, !imagePath.trimmed.isEmpty,
           let filename = URL(fileURLWithPath: imagePath).lastPathComponent.nilIfEmpty {
            return filename
        }
        if let videoPath, !videoPath.trimmed.isEmpty,
           let filename = URL(fileURLWithPath: videoPath).lastPathComponent.nilIfEmpty {
            return filename
        }
        return hasMedia ? "Attached media" : ""
    }

    var browserDetailSummary: String {
        var segments = [shapeName]
        if hasMedia {
            segments.append("Media")
        }
        if hasDrawingPreview {
            segments.append("Drawing")
        }
        if isFixed {
            segments.append("Fixed")
        }
        if isFolded {
            segments.append("Folded")
        }
        return segments.joined(separator: " · ")
    }

    func drawingPreviewItems() -> [DrawingPreviewItem] {
        let chunks = drawingEncoded
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        return chunks.compactMap { chunk in
            let lower = chunk.lowercased()
            let numbers = Self.previewNumbers(in: chunk)
            let stroke = Self.previewColor(in: chunk, prefixes: ["stroke=", "pen=", "color="])
            let fill = Self.previewColor(in: chunk, prefixes: ["fill=", "brush="])

            if lower.hasPrefix("freehand") || lower.hasPrefix("polyline") || lower.hasPrefix("1,") {
                let points = Self.previewPoints(from: numbers)
                guard points.count >= 2 else { return nil }
                return DrawingPreviewItem(kind: .polyline(points, closed: false), strokeColor: stroke, fillColor: fill)
            }

            if lower.hasPrefix("line") || lower.hasPrefix("2,") {
                guard numbers.count >= 4 else { return nil }
                return DrawingPreviewItem(
                    kind: .line(
                        FrievePoint(x: numbers[0], y: numbers[1]),
                        FrievePoint(x: numbers[2], y: numbers[3])
                    ),
                    strokeColor: stroke,
                    fillColor: fill
                )
            }

            if lower.hasPrefix("rect") || lower.hasPrefix("rectangle") || lower.hasPrefix("3,") {
                guard let rect = Self.previewRect(from: numbers) else { return nil }
                return DrawingPreviewItem(kind: .rect(rect), strokeColor: stroke, fillColor: fill)
            }

            if lower.hasPrefix("circle") || lower.hasPrefix("ellipse") || lower.hasPrefix("oval") || lower.hasPrefix("4,") {
                guard let rect = Self.previewRect(from: numbers) else { return nil }
                return DrawingPreviewItem(kind: .ellipse(rect), strokeColor: stroke, fillColor: fill)
            }

            if lower.hasPrefix("text") || lower.hasPrefix("5,") {
                let point = numbers.count >= 2 ? FrievePoint(x: numbers[0], y: numbers[1]) : FrievePoint(x: 0.1, y: 0.2)
                let caption = Self.previewText(in: chunk)
                return DrawingPreviewItem(kind: .text(point, caption), strokeColor: stroke, fillColor: fill)
            }

            if numbers.count >= 6 {
                let points = Self.previewPoints(from: numbers)
                guard points.count >= 2 else { return nil }
                return DrawingPreviewItem(kind: .polyline(points, closed: false), strokeColor: stroke, fillColor: fill)
            }

            if let rect = Self.previewRect(from: numbers) {
                return DrawingPreviewItem(kind: .rect(rect), strokeColor: stroke, fillColor: fill)
            }

            return nil
        }
    }

    private static func previewNumbers(in text: String) -> [Double] {
        var values: [Double] = []
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            if let value = Double(buffer) {
                values.append(value)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if CharacterSet(charactersIn: "+-.0123456789").contains(scalar) {
                buffer.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()

        return values
    }

    private static func previewPoints(from numbers: [Double]) -> [FrievePoint] {
        guard numbers.count >= 2 else { return [] }
        return stride(from: 0, to: numbers.count - 1, by: 2).map {
            FrievePoint(x: numbers[$0], y: numbers[$0 + 1])
        }
    }

    private static func previewRect(from numbers: [Double]) -> CGRect? {
        guard numbers.count >= 4 else { return nil }
        let x1 = numbers[0]
        let y1 = numbers[1]
        let x2 = numbers[2]
        let y2 = numbers[3]
        return CGRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )
    }

    private static func previewText(in text: String) -> String {
        if let firstQuote = text.firstIndex(of: "\""),
           let lastQuote = text.lastIndex(of: "\""),
           firstQuote < lastQuote {
            return String(text[text.index(after: firstQuote) ..< lastQuote])
        }
        if let colon = text.lastIndex(of: ":") {
            let suffix = String(text[text.index(after: colon)...]).trimmed
            if !suffix.isEmpty {
                return suffix
            }
        }
        return "Text"
    }

    private static func previewColor(in text: String, prefixes: [String]) -> Int? {
        let lower = text.lowercased()
        for prefix in prefixes {
            guard let range = lower.range(of: prefix) else { continue }
            let suffix = lower[range.upperBound...]
            let token = suffix.prefix { !$0.isWhitespace && $0 != "," && $0 != ";" }
            let cleaned = token.replacingOccurrences(of: "#", with: "")
            if let value = Int(cleaned, radix: 16) {
                return value
            }
            if let value = Int(cleaned) {
                return value
            }
        }
        return nil
    }
}

enum StatisticsGroupingKey: String, CaseIterable, Identifiable {
    case label
    case totalLinks
    case sourceLinks
    case destinationLinks
    case createdYear
    case createdMonth
    case createdDay
    case createdWeekday
    case createdHour
    case editedYear
    case editedMonth
    case editedDay
    case editedWeekday
    case editedHour
    case viewedYear
    case viewedMonth
    case viewedDay
    case viewedWeekday
    case viewedHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .label: "Label"
        case .totalLinks: "Number of Link / Total"
        case .sourceLinks: "Number of Link / Source"
        case .destinationLinks: "Number of Link / Destination"
        case .createdYear: "Created Date / Year"
        case .createdMonth: "Created Date / Month"
        case .createdDay: "Created Date / Day"
        case .createdWeekday: "Created Date / Week"
        case .createdHour: "Created Date / Hour"
        case .editedYear: "Edited Date / Year"
        case .editedMonth: "Edited Date / Month"
        case .editedDay: "Edited Date / Day"
        case .editedWeekday: "Edited Date / Week"
        case .editedHour: "Edited Date / Hour"
        case .viewedYear: "Viewed Date / Year"
        case .viewedMonth: "Viewed Date / Month"
        case .viewedDay: "Viewed Date / Day"
        case .viewedWeekday: "Viewed Date / Week"
        case .viewedHour: "Viewed Date / Hour"
        }
    }
}

struct DocumentStatisticBucket: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
    let color: Int?
    let cardIDs: [Int]
    let naturalOrder: Int
}

enum DrawingPreviewKind {
    case polyline([FrievePoint], closed: Bool)
    case line(FrievePoint, FrievePoint)
    case rect(CGRect)
    case ellipse(CGRect)
    case text(FrievePoint, String)
}

struct DrawingPreviewItem {
    let kind: DrawingPreviewKind
    let strokeColor: Int?
    let fillColor: Int?
}

struct FrieveDocument: Codable, Hashable {
    var title: String
    var metadata: [String: String]
    var focusedCardID: Int?
    var cards: [FrieveCard]
    var links: [FrieveLink]
    var cardLabels: [FrieveLabel]
    var linkLabels: [FrieveLabel]
    var sourcePath: String?

    var cardCount: Int { cards.count }
    var linkCount: Int { links.count }

    var visibleCards: [FrieveCard] {
        cards.filter { $0.visible }
    }

    var sortedCards: [FrieveCard] {
        cards.sorted { lhs, rhs in
            if lhs.isTop != rhs.isTop {
                return lhs.isTop && !rhs.isTop
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        guard !cards.isEmpty else { return (0, 1, 0, 1) }
        let xs = cards.map { $0.position.x }
        let ys = cards.map { $0.position.y }
        return (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
    }

    func card(withID id: Int?) -> FrieveCard? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    func links(for cardID: Int?) -> [FrieveLink] {
        guard let cardID else { return [] }
        return links.filter { $0.fromCardID == cardID || $0.toCardID == cardID }
    }

    func labelNames(for card: FrieveCard) -> [String] {
        let lookup = cardLabels.reduce(into: [Int: String]()) { partial, label in
            partial[label.id] = partial[label.id] ?? label.name
        }
        return card.labelIDs.compactMap { lookup[$0] }
    }

    func filteredCards(query: String) -> [FrieveCard] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return sortedCards }
        return sortedCards.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.bodyText.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func statisticsBuckets(for key: StatisticsGroupingKey, sortByCount: Bool) -> [DocumentStatisticBucket] {
        let buckets: [DocumentStatisticBucket] = switch key {
        case .label:
            labelStatisticsBuckets()
        case .totalLinks:
            linkStatisticsBuckets(direction: .total)
        case .sourceLinks:
            linkStatisticsBuckets(direction: .source)
        case .destinationLinks:
            linkStatisticsBuckets(direction: .destination)
        case .createdYear:
            dateStatisticsBuckets(field: .created, granularity: .year)
        case .createdMonth:
            dateStatisticsBuckets(field: .created, granularity: .month)
        case .createdDay:
            dateStatisticsBuckets(field: .created, granularity: .day)
        case .createdWeekday:
            dateStatisticsBuckets(field: .created, granularity: .weekday)
        case .createdHour:
            dateStatisticsBuckets(field: .created, granularity: .hour)
        case .editedYear:
            dateStatisticsBuckets(field: .updated, granularity: .year)
        case .editedMonth:
            dateStatisticsBuckets(field: .updated, granularity: .month)
        case .editedDay:
            dateStatisticsBuckets(field: .updated, granularity: .day)
        case .editedWeekday:
            dateStatisticsBuckets(field: .updated, granularity: .weekday)
        case .editedHour:
            dateStatisticsBuckets(field: .updated, granularity: .hour)
        case .viewedYear:
            dateStatisticsBuckets(field: .viewed, granularity: .year)
        case .viewedMonth:
            dateStatisticsBuckets(field: .viewed, granularity: .month)
        case .viewedDay:
            dateStatisticsBuckets(field: .viewed, granularity: .day)
        case .viewedWeekday:
            dateStatisticsBuckets(field: .viewed, granularity: .weekday)
        case .viewedHour:
            dateStatisticsBuckets(field: .viewed, granularity: .hour)
        }

        guard sortByCount else {
            return buckets
        }

        return buckets.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.naturalOrder < rhs.naturalOrder
        }
    }

    func statisticsCards(for bucket: DocumentStatisticBucket) -> [FrieveCard] {
        let includedIDs = Set(bucket.cardIDs)
        return sortedCards.filter { includedIDs.contains($0.id) }
    }

    private func labelStatisticsBuckets() -> [DocumentStatisticBucket] {
        cardLabels
            .filter(\.enabled)
            .enumerated()
            .map { offset, label in
                let cardIDs = cards
                    .filter { $0.labelIDs.contains(label.id) }
                    .map(\.id)
                return DocumentStatisticBucket(
                    id: "label-\(label.id)",
                    name: label.name,
                    count: cardIDs.count,
                    color: label.color,
                    cardIDs: cardIDs,
                    naturalOrder: offset
                )
            }
    }

    private func linkStatisticsBuckets(direction: StatisticsLinkDirection) -> [DocumentStatisticBucket] {
        let countsByCardID = cards.reduce(into: [Int: Int]()) { partial, card in
            partial[card.id] = 0
        }
        let resolvedCountsByCardID = links.reduce(into: countsByCardID) { partial, link in
            if direction == .total || direction == .source {
                partial[link.fromCardID, default: 0] += 1
            }
            if direction == .total || direction == .destination {
                partial[link.toCardID, default: 0] += 1
            }
        }
        let maximumLinkCount = resolvedCountsByCardID.values.max() ?? 0

        return (0 ... maximumLinkCount).map { linkCount in
            let cardIDs = cards
                .filter { resolvedCountsByCardID[$0.id, default: 0] == linkCount }
                .map(\.id)
            return DocumentStatisticBucket(
                id: "links-\(direction.rawValue)-\(linkCount)",
                name: "\(linkCount) Links",
                count: cardIDs.count,
                color: nil,
                cardIDs: cardIDs,
                naturalOrder: linkCount
            )
        }
    }

    private func dateStatisticsBuckets(field: StatisticsDateField, granularity: StatisticsDateGranularity) -> [DocumentStatisticBucket] {
        let parsedDates = cards.map { card in
            (cardID: card.id, date: statisticsDate(for: card, field: field))
        }
        let knownDates = parsedDates.compactMap { entry -> (Int, Date)? in
            guard let date = entry.date else { return nil }
            return (entry.cardID, date)
        }
        let orderedDefinitions = knownDates
            .sorted { $0.1 > $1.1 }
            .reduce(into: [StatisticsBucketDefinition]()) { partial, entry in
                let definition = statisticsBucketDefinition(for: entry.1, granularity: granularity)
                if !partial.contains(where: { $0.id == definition.id }) {
                    partial.append(definition)
                }
            }

        var cardIDsByBucketID = Dictionary(uniqueKeysWithValues: orderedDefinitions.map { ($0.id, [Int]()) })
        var unknownCardIDs: [Int] = []

        for entry in parsedDates {
            guard let date = entry.date else {
                unknownCardIDs.append(entry.cardID)
                continue
            }
            let definition = statisticsBucketDefinition(for: date, granularity: granularity)
            cardIDsByBucketID[definition.id, default: []].append(entry.cardID)
        }

        var buckets = orderedDefinitions.enumerated().map { offset, definition in
            let cardIDs = cardIDsByBucketID[definition.id] ?? []
            return DocumentStatisticBucket(
                id: definition.id,
                name: definition.title,
                count: cardIDs.count,
                color: nil,
                cardIDs: cardIDs,
                naturalOrder: offset
            )
        }

        if !unknownCardIDs.isEmpty {
            buckets.append(
                DocumentStatisticBucket(
                    id: "date-\(field.rawValue)-\(granularity.rawValue)-unknown",
                    name: "Unknown",
                    count: unknownCardIDs.count,
                    color: nil,
                    cardIDs: unknownCardIDs,
                    naturalOrder: buckets.count
                )
            )
        }

        return buckets
    }

    private func statisticsDate(for card: FrieveCard, field: StatisticsDateField) -> Date? {
        let rawValue: String = switch field {
        case .created:
            card.created
        case .updated:
            card.updated
        case .viewed:
            card.viewed
        }
        return StatisticsDateParser.parse(rawValue)
    }

    private func statisticsBucketDefinition(for date: Date, granularity: StatisticsDateGranularity) -> StatisticsBucketDefinition {
        let components = Self.statisticsCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        switch granularity {
        case .year:
            let year = components.year ?? 0
            return StatisticsBucketDefinition(id: "year-\(year)", title: "\(year)")
        case .month:
            let year = components.year ?? 0
            let month = components.month ?? 0
            return StatisticsBucketDefinition(id: String(format: "month-%04d-%02d", year, month), title: "\(month)/\(year)")
        case .day:
            let year = components.year ?? 0
            let month = components.month ?? 0
            let day = components.day ?? 0
            return StatisticsBucketDefinition(
                id: String(format: "day-%04d-%02d-%02d", year, month, day),
                title: StatisticsDateParser.shortDayLabel(for: date)
            )
        case .weekday:
            let weekday = (components.weekday ?? 2)
            let normalizedWeekday = (weekday + 5) % 7
            return StatisticsBucketDefinition(
                id: "weekday-\(normalizedWeekday)",
                title: StatisticsDateParser.weekdayLabels[normalizedWeekday]
            )
        case .hour:
            let hour = components.hour ?? 0
            return StatisticsBucketDefinition(id: "hour-\(hour)", title: "\(hour)")
        }
    }

    func childCardIDs(for parentID: Int) -> [Int] {
        links
            .filter { $0.fromCardID == parentID }
            .map(\.toCardID)
    }

    func rootCards() -> [FrieveCard] {
        let inboundIDs = Set(links.map(\.toCardID))
        let roots = sortedCards.filter { card in
            card.isTop || !inboundIDs.contains(card.id)
        }
        return roots.isEmpty ? sortedCards : roots
    }

    func hierarchicalText() -> String {
        let rootIDs = rootCards().map(\.id)
        var visited = Set<Int>()
        var lines: [String] = []

        func appendCard(_ cardID: Int, depth: Int) {
            guard !visited.contains(cardID), let card = card(withID: cardID) else { return }
            visited.insert(cardID)
            let prefix = String(repeating: "  ", count: depth) + "- "
            lines.append(prefix + card.title)
            let body = card.bodyText.trimmed
            if !body.isEmpty {
                for bodyLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append(String(repeating: "  ", count: depth + 1) + String(bodyLine))
                }
            }
            for childID in childCardIDs(for: cardID) {
                appendCard(childID, depth: depth + 1)
            }
        }

        for rootID in rootIDs {
            appendCard(rootID, depth: 0)
        }

        for card in sortedCards where !visited.contains(card.id) {
            appendCard(card.id, depth: 0)
        }

        return lines.joined(separator: "\n")
    }

    func htmlDocument(title: String? = nil) -> String {
        let documentTitle = (title ?? self.title).trimmed.isEmpty ? "Frieve Document" : (title ?? self.title)
        let rows = sortedCards.map { card in
            let labels = labelNames(for: card).joined(separator: ", ")
            let escapedTitle = card.title.htmlEscaped
            let escapedBody = card.bodyText.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
            let escapedLabels = labels.htmlEscaped
            return "<article class=\"card\"><h2>\(escapedTitle)</h2><p>\(escapedBody)</p><p class=\"meta\">Labels: \(escapedLabels.isEmpty ? "None" : escapedLabels) · Score: \(card.score)</p></article>"
        }
        .joined(separator: "\n")

        return """
        <!doctype html>
        <html lang=\"en\">
        <head>
          <meta charset=\"utf-8\">
          <title>\(documentTitle.htmlEscaped)</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; background: #f7f7f9; color: #1f2937; }
            h1 { margin-bottom: 24px; }
            .card { background: white; border-radius: 12px; padding: 18px 20px; margin-bottom: 14px; box-shadow: 0 4px 14px rgba(0,0,0,0.06); }
            .meta { color: #6b7280; font-size: 13px; }
          </style>
        </head>
        <body>
          <h1>\(documentTitle.htmlEscaped)</h1>
          \(rows)
        </body>
        </html>
        """
    }

    mutating func ensureFocusedCard() {
        if focusedCardID == nil {
            focusedCardID = sortedCards.first?.id
        }
    }

    mutating func updateCard(_ cardID: Int, mutate: (inout FrieveCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        mutate(&cards[index])
    }

    mutating func addCard(title: String, linkedFrom parentID: Int? = nil) -> Int {
        let newID = (cards.map { $0.id }.max() ?? -1) + 1
        let seed = card(withID: parentID)
        let newPosition = FrievePoint(
            x: (seed?.position.x ?? 0.5) + (parentID == nil ? 0.03 : 0.08),
            y: (seed?.position.y ?? 0.5) + (parentID == nil ? 0.03 : 0.08)
        )
        let card = FrieveCard(
            id: newID,
            title: title,
            bodyText: "",
            drawingEncoded: "",
            visible: true,
            shape: seed?.shape ?? 2,
            size: seed?.size ?? 100,
            isTop: parentID == nil,
            isFixed: false,
            isFolded: false,
            position: newPosition,
            created: isoTimestamp(),
            updated: isoTimestamp(),
            viewed: isoTimestamp(),
            labelIDs: [],
            score: seed?.score ?? 0,
            imagePath: nil,
            videoPath: nil
        )
        cards.append(card)
        if let parentID {
            links.append(
                FrieveLink(
                    fromCardID: parentID,
                    toCardID: newID,
                    directionVisible: true,
                    shape: 5,
                    labelIDs: [],
                    name: ""
                )
            )
        }
        focusedCardID = newID
        return newID
    }

    mutating func addSiblingCard(for cardID: Int?) -> Int {
        guard let cardID, let source = card(withID: cardID) else {
            return addCard(title: "New Card")
        }
        let siblingID = addCard(title: "Sibling of \(source.title)")
        updateCard(siblingID) { sibling in
            sibling.position = FrievePoint(x: source.position.x + 0.12, y: source.position.y)
            sibling.shape = source.shape
            sibling.size = source.size
        }
        return siblingID
    }

    mutating func deleteCard(_ cardID: Int) {
        cards.removeAll { $0.id == cardID }
        links.removeAll { $0.fromCardID == cardID || $0.toCardID == cardID }
        if focusedCardID == cardID {
            focusedCardID = sortedCards.first?.id
        }
    }

    mutating func moveCard(_ cardID: Int, dx: Double, dy: Double) {
        updateCard(cardID) { card in
            card.position.x += dx
            card.position.y += dy
            card.updated = isoTimestamp()
        }
    }

    mutating func touchFocusedCard() {
        guard let focusedCardID else { return }
        updateCard(focusedCardID) { card in
            card.viewed = isoTimestamp()
        }
    }

    static func placeholder() -> FrieveDocument {
        var document = FrieveDocument(
            title: "Frieve Editor",
            metadata: [
                "Version": "1",
                "DefaultView": "0",
                "AutoSave": "0",
                "AutoReload": "0"
            ],
            focusedCardID: 0,
            cards: [
                FrieveCard(
                    id: 0,
                    title: "Frieve Editor",
                    bodyText: "A macOS-native workspace for idea processing.",
                    drawingEncoded: "",
                    visible: true,
                    shape: 2,
                    size: 160,
                    isTop: true,
                    isFixed: false,
                    isFolded: false,
                    position: FrievePoint(x: 0.5, y: 0.45),
                    created: isoTimestamp(),
                    updated: isoTimestamp(),
                    viewed: isoTimestamp(),
                    labelIDs: [1],
                    score: 1.0,
                    imagePath: nil,
                    videoPath: nil
                )
            ],
            links: [],
            cardLabels: [
                FrieveLabel(
                    id: 1,
                    name: "Overview",
                    color: 0x71CC2E,
                    enabled: true,
                    show: true,
                    hide: false,
                    fold: false,
                    size: 100
                )
            ],
            linkLabels: [],
            sourcePath: nil
        )
        document.ensureFocusedCard()
        return document
    }
}

func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private enum StatisticsLinkDirection: String {
    case total
    case source
    case destination
}

private enum StatisticsDateField: String {
    case created
    case updated
    case viewed
}

private enum StatisticsDateGranularity: String {
    case year
    case month
    case day
    case weekday
    case hour
}

private struct StatisticsBucketDefinition {
    let id: String
    let title: String
}

private enum StatisticsDateParser {
    static let weekdayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    static func parse(_ rawValue: String) -> Date? {
        let trimmed = rawValue.trimmed
        guard !trimmed.isEmpty else { return nil }

        let iso8601Fractional = ISO8601DateFormatter()
        iso8601Fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]

        if let date = iso8601Fractional.date(from: trimmed) ?? iso8601.date(from: trimmed) {
            return date
        }

        for formatter in makeFormatters() {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        if let numericValue = Double(trimmed) {
            if numericValue > 100_000_000 {
                return Date(timeIntervalSince1970: numericValue)
            }
            return delphiReferenceDate.addingTimeInterval(numericValue * 86_400)
        }

        return nil
    }

    static func shortDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = FrieveDocument.statisticsCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static let delphiReferenceDate: Date = {
        var components = DateComponents()
        components.calendar = FrieveDocument.statisticsCalendar
        components.timeZone = .autoupdatingCurrent
        components.year = 1899
        components.month = 12
        components.day = 30
        return components.date ?? Date(timeIntervalSince1970: 0)
    }()

    private static func makeFormatters() -> [DateFormatter] {
        [
            makeFormatter("yyyy-MM-dd HH:mm:ss"),
            makeFormatter("yyyy/MM/dd HH:mm:ss"),
            makeFormatter("yyyy/MM/dd HH:mm"),
            makeFormatter("yyyy-MM-dd HH:mm"),
            makeFormatter("yyyy/MM/dd"),
            makeFormatter("yyyy-MM-dd"),
            makeFormatter("M/d/yyyy H:mm:ss"),
            makeFormatter("M/d/yyyy H:mm"),
            makeFormatter("M/d/yyyy"),
            makeFormatter("M/d/yy H:mm:ss"),
            makeFormatter("M/d/yy H:mm"),
            makeFormatter("M/d/yy")
        ]
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = FrieveDocument.statisticsCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}

private extension FrieveDocument {
    static let statisticsCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        return calendar
    }()
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
