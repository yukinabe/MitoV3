//  CardImport.swift
//  Bulk import (CSV/JSON/Anki), zip + sqlite helpers, deck templates, import sheet.
//  Extracted from FlashcardsView.swift (behavior-preserving refactor).

import SwiftUI
import UniformTypeIdentifiers
import Compression
import SQLite3

// MARK: - Bulk import

struct ParsedCard {
    let front: String
    let back: String
    let tags: [String]
}

enum ImportFormat: String, CaseIterable, Identifiable {
    case lines, csv, json
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lines: "LINES"
        case .csv: "CSV"
        case .json: "JSON"
        }
    }
    var hint: String {
        switch self {
        case .lines: "One card per line, front and back split by a tab, ; or ,"
        case .csv: "front,back per row (a front,back header row is skipped)"
        case .json: #"[{"front":"…","back":"…","tags":["…"]}]  (q/a also accepted)"#
        }
    }
}

enum CardImporter {
    static func parse(_ text: String, format: ImportFormat) -> [ParsedCard] {
        switch format {
        case .lines: return parseLines(text)
        case .csv: return parseCSV(text)
        case .json: return parseJSON(text)
        }
    }

    private static func parseLines(_ text: String) -> [ParsedCard] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Skip blanks and Anki plain-text headers (#separator:tab, #html:true…).
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            // Tab-separated (Anki "Notes in Plain Text"): front, back, [tags].
            if line.contains("\t") {
                let cols = line.components(separatedBy: "\t")
                let front = clean(cols[0])
                let back = cols.count > 1 ? clean(cols[1]) : ""
                guard !front.isEmpty, !back.isEmpty else { return nil }
                return ParsedCard(front: front, back: back, tags: cols.count > 2 ? tagList(cols[2]) : [])
            }
            for delimiter in [" | ", ";", " - ", ","] {
                if let range = line.range(of: delimiter) {
                    let front = clean(String(line[..<range.lowerBound]))
                    let back = clean(String(line[range.upperBound...]))
                    if !front.isEmpty, !back.isEmpty {
                        return ParsedCard(front: front, back: back, tags: [])
                    }
                }
            }
            return nil
        }
    }

    private static func parseCSV(_ text: String) -> [ParsedCard] {
        var rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.hasPrefix("#") }
        if let header = rows.first?.lowercased().replacingOccurrences(of: " ", with: ""),
           header.hasPrefix("front,back") {
            rows.removeFirst()
        }
        return rows.compactMap { row in
            let cols = splitCSVRow(row)
            guard cols.count >= 2 else { return nil }
            let front = clean(cols[0])
            let back = clean(cols[1])
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return ParsedCard(front: front, back: back, tags: cols.count >= 3 ? tagList(cols[2]) : [])
        }
    }

    /// Split a tag field on spaces / semicolons / commas.
    static func tagList(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Strip HTML tags and decode common entities — Anki fields are HTML.
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (key, value) in entities { s = s.replacingOccurrences(of: key, with: value) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in row {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == ",", !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func parseJSON(_ text: String) -> [ParsedCard] {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { obj in
            let frontRaw = (obj["front"] ?? obj["q"] ?? obj["question"]) as? String
            let backRaw = (obj["back"] ?? obj["a"] ?? obj["answer"]) as? String
            guard let front = frontRaw.map(clean), !front.isEmpty,
                  let back = backRaw.map(clean), !back.isEmpty else { return nil }
            let tags = (obj["tags"] as? [String])?.map { $0.lowercased() } ?? []
            return ParsedCard(front: front, back: back, tags: tags)
        }
    }
}

/// Minimal read-only ZIP extractor (no dependency): finds one entry by name
/// suffix and inflates stored/deflated data. Enough to crack open an .apkg.
enum MiniZip {
    static func extract(_ candidates: [String], from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 22, let eocd = findEOCD(bytes) else { return nil }
        let total = readU16(bytes, eocd + 10)
        var p = Int(readU32(bytes, eocd + 16))   // central directory offset
        for _ in 0..<total {
            guard p + 46 <= bytes.count, readU32(bytes, p) == 0x02014b50 else { break }
            let method = readU16(bytes, p + 10)
            let compSize = Int(readU32(bytes, p + 20))
            let uncompSize = Int(readU32(bytes, p + 24))
            let fnLen = readU16(bytes, p + 28)
            let extraLen = readU16(bytes, p + 30)
            let commentLen = readU16(bytes, p + 32)
            let localOff = Int(readU32(bytes, p + 42))
            let nameStart = p + 46
            guard nameStart + fnLen <= bytes.count else { break }
            let name = String(bytes: bytes[nameStart..<nameStart + fnLen], encoding: .utf8) ?? ""
            if candidates.contains(where: { name.hasSuffix($0) }) {
                return readEntry(bytes, localOffset: localOff, method: method, compSize: compSize, uncompSize: uncompSize)
            }
            p = nameStart + fnLen + extraLen + commentLen
        }
        return nil
    }

    private static func readEntry(_ bytes: [UInt8], localOffset: Int, method: Int, compSize: Int, uncompSize: Int) -> Data? {
        guard localOffset + 30 <= bytes.count, readU32(bytes, localOffset) == 0x04034b50 else { return nil }
        let fnLen = readU16(bytes, localOffset + 26)
        let extraLen = readU16(bytes, localOffset + 28)
        let start = localOffset + 30 + fnLen + extraLen
        guard start + compSize <= bytes.count else { return nil }
        let comp = Array(bytes[start..<start + compSize])
        if method == 0 { return Data(comp) }           // stored
        if method == 8 { return inflate(comp, expected: uncompSize) }  // deflate
        return nil
    }

    private static func inflate(_ src: [UInt8], expected: Int) -> Data? {
        let cap = max(expected, 1)
        var dst = [UInt8](repeating: 0, count: cap)
        let written = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, cap, s.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written > 0 ? Data(dst[0..<written]) : nil
    }

    private static func findEOCD(_ b: [UInt8]) -> Int? {
        var i = b.count - 22
        let lower = max(0, b.count - 22 - 65_536)
        while i >= lower {
            if readU32(b, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func readU16(_ b: [UInt8], _ o: Int) -> Int {
        guard o + 1 < b.count else { return 0 }
        return Int(b[o]) | (Int(b[o + 1]) << 8)
    }
    private static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 3 < b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}

/// Reads an Anki .apkg (legacy `collection.anki2` SQLite) into flashcards.
/// Returns nil for the newer zstd `.anki21b` format or unreadable packages.
enum AnkiImporter {
    static func parse(_ data: Data) -> [ParsedCard]? {
        // Legacy: collection.anki2 / .anki21 is plain SQLite inside the zip.
        if let dbData = MiniZip.extract(["collection.anki2", "collection.anki21"], from: data) {
            return readNotes(dbData)
        }
        // Modern (Anki 2.1.50+): collection.anki21b is zstd-compressed SQLite.
        if let compressed = MiniZip.extract(["collection.anki21b"], from: data),
           let dbData = zstdDecompress(compressed) {
            return readNotes(dbData)
        }
        return nil
    }

    private static func readNotes(_ dbData: Data) -> [ParsedCard]? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mito_anki_\(UUID().uuidString).anki2")
        guard (try? dbData.write(to: tmp)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open(tmp.path, &db) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        // notes.flds = fields joined by the 0x1f unit separator; tags space-separated.
        guard sqlite3_prepare_v2(db, "SELECT flds, tags FROM notes", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var cards: [ParsedCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let fldsC = sqlite3_column_text(stmt, 0) else { continue }
            let fields = String(cString: fldsC).components(separatedBy: "\u{1f}")
            let tagsStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let front = CardImporter.clean(fields[0])
            let back = fields.count > 1 ? CardImporter.clean(fields[1]) : ""
            guard !front.isEmpty, !back.isEmpty else { continue }
            cards.append(ParsedCard(front: front, back: back, tags: CardImporter.tagList(tagsStr)))
        }
        return cards.isEmpty ? nil : cards
    }

    /// Decompress a single zstd frame via the vendored zstd decoder.
    private static func zstdDecompress(_ src: Data) -> Data? {
        let bytes = [UInt8](src)
        let contentSize = bytes.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, bytes.count) }
        // Reject the ZSTD_CONTENTSIZE_UNKNOWN / _ERROR sentinels (huge values).
        guard contentSize > 0, contentSize < 300_000_000 else { return nil }
        var dst = [UInt8](repeating: 0, count: Int(contentSize))
        let written = dst.withUnsafeMutableBytes { d in
            bytes.withUnsafeBytes { s in
                ZSTD_decompress(d.baseAddress, Int(contentSize), s.baseAddress, bytes.count)
            }
        }
        guard ZSTD_isError(written) == 0 else { return nil }
        return Data(dst[0..<written])
    }
}

struct DeckTemplate: Identifiable {
    let id: String
    let name: String
    let cards: [ParsedCard]

    static let all: [DeckTemplate] = [
        DeckTemplate(id: "tmpl-cell", name: "Cell Biology", cards: [
            ParsedCard(front: "What organelle makes most ATP?", back: "The mitochondrion.", tags: ["cell"]),
            ParsedCard(front: "What does the nucleus store?", back: "The cell's DNA.", tags: ["cell"]),
            ParsedCard(front: "Where are proteins assembled?", back: "On ribosomes.", tags: ["cell"]),
            ParsedCard(front: "What packages and ships proteins?", back: "The Golgi apparatus.", tags: ["cell"]),
            ParsedCard(front: "What controls what enters the cell?", back: "The cell membrane.", tags: ["cell"])
        ]),
        DeckTemplate(id: "tmpl-es", name: "Spanish 101", cards: [
            ParsedCard(front: "hello", back: "hola", tags: ["spanish"]),
            ParsedCard(front: "thank you", back: "gracias", tags: ["spanish"]),
            ParsedCard(front: "water", back: "agua", tags: ["spanish"]),
            ParsedCard(front: "to eat", back: "comer", tags: ["spanish"]),
            ParsedCard(front: "good morning", back: "buenos días", tags: ["spanish"])
        ]),
        DeckTemplate(id: "tmpl-cap", name: "World Capitals", cards: [
            ParsedCard(front: "Japan", back: "Tokyo", tags: ["geography"]),
            ParsedCard(front: "France", back: "Paris", tags: ["geography"]),
            ParsedCard(front: "Brazil", back: "Brasília", tags: ["geography"]),
            ParsedCard(front: "Egypt", back: "Cairo", tags: ["geography"]),
            ParsedCard(front: "Canada", back: "Ottawa", tags: ["geography"])
        ])
    ]
}

struct ImportSheet: View {
    let existingDeckName: String?
    let onCancel: () -> Void
    let onImport: (_ deckName: String?, _ cards: [ParsedCard]) -> Void

    @State private var format: ImportFormat = .lines
    @State private var text = ""
    @State private var newDeckName = ""
    @State private var showFileImporter = false
    @State private var showApkgImporter = false
    @State private var importMessage = ""

    private var creatingNew: Bool { existingDeckName == nil }
    private var parsed: [ParsedCard] { CardImporter.parse(text, format: format) }
    private var canImport: Bool {
        !parsed.isEmpty && (!creatingNew || !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(creatingNew ? "IMPORT NEW DECK" : "IMPORT INTO \(existingDeckName!.uppercased())")
                    .pixelText(size: 13, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button(action: onCancel) {
                    Text("×")
                        .font(.custom(MitoFont.regular, size: 26))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
                .buttonStyle(.plain)
            }

            if creatingNew {
                TextField("Deck name", text: $newDeckName)
                    .font(.custom(MitoFont.regular, size: 17))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .padding(8)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            HStack(spacing: 6) {
                ForEach(ImportFormat.allCases) { item in
                    Button { format = item } label: {
                        Text(item.title)
                            .pixelText(size: 9, color: format == item ? Color(hex: "18100A") : Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(format == item ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(format.hint)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "6B4324"))
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom(MitoFont.regular, size: 15))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 132)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                if text.isEmpty {
                    Text("Paste your cards here…")
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "8A6B42"))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Button { showFileImporter = true } label: {
                    Text("LOAD FILE")
                        .pixelText(size: 9, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(parsed.isEmpty ? "0 cards" : "✓ \(parsed.count) cards")
                    .pixelText(size: 10, color: parsed.isEmpty ? Color(hex: "8A6B42") : Color(hex: "4A8A3C"))
            }

            Button {
                importMessage = ""
                showApkgImporter = true
            } label: {
                Text("⬇ IMPORT ANKI DECK (.apkg)")
                    .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(hex: "6B4324"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .buttonStyle(.plain)

            if !importMessage.isEmpty {
                Text(importMessage)
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "C4452F"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Button {
                    onImport(creatingNew ? newDeckName.trimmingCharacters(in: .whitespaces) : nil, parsed)
                } label: {
                    Text(parsed.isEmpty ? "IMPORT" : "IMPORT \(parsed.count)")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canImport ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canImport)
            }
        }
        .padding(14)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .json, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
            text = loaded
            switch url.pathExtension.lowercased() {
            case "json": format = .json
            case "csv": format = .csv
            default: break
            }
        }
        .fileImporter(isPresented: $showApkgImporter, allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importMessage = "Couldn't read that file."
                return
            }
            guard let cards = AnkiImporter.parse(data), !cards.isEmpty else {
                importMessage = "Couldn't read this file as an Anki deck. Make sure it's a .apkg exported from Anki."
                return
            }
            let name = creatingNew ? url.deletingPathExtension().lastPathComponent : nil
            onImport(name, cards)
        }
    }
}
