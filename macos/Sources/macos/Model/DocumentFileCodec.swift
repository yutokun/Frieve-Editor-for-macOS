import Foundation

enum FrieveFileError: LocalizedError {
    case invalidMagicLine
    case malformedSection(String)
    case unreadableFile(URL)
    case unsupportedFile(URL)

    var errorDescription: String? {
        switch self {
        case .invalidMagicLine:
            return "The file does not begin with the FIP2/1 magic line."
        case let .malformedSection(section):
            return "The file contains a malformed section: \(section)."
        case let .unreadableFile(url):
            return "The file at \(url.path) could not be read."
        case let .unsupportedFile(url):
            return "The file at \(url.path) is not a supported Frieve document."
        }
    }
}

enum DocumentFileCodec {
    static func load(url: URL) throws -> FrieveDocument {
        guard let data = try? Data(contentsOf: url) else {
            throw FrieveFileError.unreadableFile(url)
        }

        if url.pathExtension.lowercased() == "fip2" {
            return try FIP2Codec.load(data: data, sourcePath: url.path)
        }

        let text = String(decoding: data, as: UTF8.self)
        let firstNonEmpty = text
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .map(\.trimmed)
            .first { !$0.isEmpty }

        if firstNonEmpty == "FIP2/1" {
            return try FIP2Codec.load(text: text, sourcePath: url.path)
        }

        if url.pathExtension.lowercased() == "fip" || text.contains("[CardData]") {
            return try LegacyFIPCodec.load(text: text, sourcePath: url.path)
        }

        throw FrieveFileError.unsupportedFile(url)
    }

    static func save(document: FrieveDocument, to url: URL) throws {
        let serialized = FIP2Codec.save(document: document)
        try serialized.write(to: url, atomically: true, encoding: .utf8)
    }
}
