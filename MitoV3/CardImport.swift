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
    let sched: SchedulingState?

    init(front: String, back: String, tags: [String], sched: SchedulingState? = nil) {
        self.front = front
        self.back = back
        self.tags = tags
        self.sched = sched
    }
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
        text.split(whereSeparator: \.isNewline).flatMap { raw -> [ParsedCard] in
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Skip blanks and Anki plain-text headers (#separator:tab, #html:true…).
            guard !line.isEmpty, !line.hasPrefix("#") else { return [] }
            // Tab-separated (Anki "Notes in Plain Text"): front, back, [tags].
            if line.contains("\t") {
                let cols = line.components(separatedBy: "\t")
                let frontRaw = cols[0]
                let front = clean(frontRaw)
                let back = cols.count > 1 ? clean(cols[1]) : ""
                let tags = cols.count > 2 ? tagList(cols[2]) : []
                if let cloze = ClozeImporter.cards(from: frontRaw, tags: tags), !cloze.isEmpty {
                    return cloze
                }
                guard !front.isEmpty, !back.isEmpty else { return [] }
                return [ParsedCard(front: front, back: back, tags: tags)]
            }
            for delimiter in [" | ", ";", " - ", ","] {
                if let range = line.range(of: delimiter) {
                    let frontRaw = String(line[..<range.lowerBound])
                    let front = clean(frontRaw)
                    let back = clean(String(line[range.upperBound...]))
                    if let cloze = ClozeImporter.cards(from: frontRaw, tags: []), !cloze.isEmpty {
                        return cloze
                    }
                    if !front.isEmpty, !back.isEmpty {
                        return [ParsedCard(front: front, back: back, tags: [])]
                    }
                }
            }
            if let cloze = ClozeImporter.cards(from: line, tags: []), !cloze.isEmpty {
                return cloze
            }
            return []
        }
    }

    private static func parseCSV(_ text: String) -> [ParsedCard] {
        var rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.hasPrefix("#") }
        if let header = rows.first?.lowercased().replacingOccurrences(of: " ", with: ""),
           header.hasPrefix("front,back") {
            rows.removeFirst()
        }
        return rows.flatMap { row -> [ParsedCard] in
            let cols = splitCSVRow(row)
            guard cols.count >= 2 else { return [] }
            let frontRaw = cols[0]
            let front = clean(frontRaw)
            let back = clean(cols[1])
            let tags = cols.count >= 3 ? tagList(cols[2]) : []
            if let cloze = ClozeImporter.cards(from: frontRaw, tags: tags), !cloze.isEmpty {
                return cloze
            }
            guard !front.isEmpty, !back.isEmpty else { return [] }
            return [ParsedCard(front: front, back: back, tags: tags)]
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
        return array.flatMap { obj -> [ParsedCard] in
            let frontRaw = (obj["front"] ?? obj["q"] ?? obj["question"]) as? String
            let backRaw = (obj["back"] ?? obj["a"] ?? obj["answer"]) as? String
            let tags = (obj["tags"] as? [String])?.map { $0.lowercased() } ?? []
            if let frontRaw, let cloze = ClozeImporter.cards(from: frontRaw, tags: tags), !cloze.isEmpty {
                return cloze
            }
            guard let front = frontRaw.map(clean), !front.isEmpty,
                  let back = backRaw.map(clean), !back.isEmpty else { return [] }
            return [ParsedCard(front: front, back: back, tags: tags)]
        }
    }
}

enum ClozeImporter {
    private struct Token {
        let index: Int
        let answer: String
        let hint: String?
        let range: NSRange
    }

    static func cards(from raw: String, tags: [String], schedule: ((Int) -> SchedulingState?)? = nil) -> [ParsedCard]? {
        let tokens = clozeTokens(in: raw)
        guard !tokens.isEmpty else { return nil }
        let clozeTags = Array(Set(tags + ["cloze"])).sorted()
        let indexes = Array(Set(tokens.map(\.index))).sorted()
        return indexes.compactMap { index in
            let front = replaceClozes(in: raw, tokens: tokens, target: index, revealTarget: false)
            let backAnswers = tokens
                .filter { $0.index == index }
                .map { CardImporter.clean($0.answer) }
                .filter { !$0.isEmpty }
            let back = Array(Set(backAnswers)).sorted().joined(separator: "; ")
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return ParsedCard(front: front, back: back, tags: clozeTags, sched: schedule?(index))
        }
    }

    private static func clozeTokens(in raw: String) -> [Token] {
        let ns = raw as NSString
        let pattern = #"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let indexRange = Range(match.range(at: 1), in: raw),
                  let index = Int(raw[indexRange]),
                  let answerRange = Range(match.range(at: 2), in: raw) else { return nil }
            let hint: String?
            if match.numberOfRanges > 3,
               match.range(at: 3).location != NSNotFound,
               let hintRange = Range(match.range(at: 3), in: raw) {
                hint = String(raw[hintRange])
            } else {
                hint = nil
            }
            return Token(index: index, answer: String(raw[answerRange]), hint: hint, range: match.range)
        }
    }

    private static func replaceClozes(in raw: String, tokens: [Token], target: Int, revealTarget: Bool) -> String {
        var result = raw as NSString
        for token in tokens.sorted(by: { $0.range.location > $1.range.location }) {
            let replacement: String
            if token.index == target, !revealTarget {
                let label = token.hint.map(CardImporter.clean).flatMap { $0.isEmpty ? nil : $0 } ?? "..."
                replacement = "[\(label)]"
            } else {
                replacement = token.answer
            }
            result = result.replacingCharacters(in: token.range, with: replacement) as NSString
        }
        return CardImporter.clean(result as String)
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

/// Reads an Anki .apkg into flashcards, including cloze cards and the best
/// scheduling state we can recover from Anki's `cards` rows.
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

    private struct AnkiCardRow {
        let id: Int64
        let ord: Int
        let type: Int
        let queue: Int
        let due: Int
        let interval: Int
        let factor: Int
        let reps: Int
        let lapses: Int
        let data: String
        let modified: Int
        let fields: [String]
        let tags: [String]
    }

    private static func readNotes(_ dbData: Data) -> [ParsedCard]? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mito_anki_\(UUID().uuidString).anki2")
        guard (try? dbData.write(to: tmp)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open(tmp.path, &db) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }

        let collectionCreated = collectionCreatedDate(db)
        if let cards = readCards(db, collectionCreated: collectionCreated), !cards.isEmpty {
            return cards
        }

        return readLegacyNotes(db)
    }

    private static func readCards(_ db: OpaquePointer?, collectionCreated: Date) -> [ParsedCard]? {
        var stmt: OpaquePointer?
        let sql = """
        SELECT cards.id, cards.ord, cards.type, cards.queue, cards.due, cards.ivl,
               cards.factor, cards.reps, cards.lapses, cards.data, cards.mod,
               notes.flds, notes.tags
        FROM cards
        JOIN notes ON notes.id = cards.nid
        ORDER BY notes.id, cards.ord
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var cards: [ParsedCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = AnkiCardRow(
                id: sqlite3_column_int64(stmt, 0),
                ord: Int(sqlite3_column_int(stmt, 1)),
                type: Int(sqlite3_column_int(stmt, 2)),
                queue: Int(sqlite3_column_int(stmt, 3)),
                due: Int(sqlite3_column_int(stmt, 4)),
                interval: Int(sqlite3_column_int(stmt, 5)),
                factor: Int(sqlite3_column_int(stmt, 6)),
                reps: Int(sqlite3_column_int(stmt, 7)),
                lapses: Int(sqlite3_column_int(stmt, 8)),
                data: textColumn(stmt, 9),
                modified: Int(sqlite3_column_int(stmt, 10)),
                fields: textColumn(stmt, 11).components(separatedBy: "\u{1f}"),
                tags: CardImporter.tagList(textColumn(stmt, 12))
            )
            guard let first = row.fields.first else { continue }
            let sched = schedulingState(for: row, collectionCreated: collectionCreated)
            if let clozeCards = ClozeImporter.cards(from: first, tags: row.tags, schedule: { index in
                index == row.ord + 1 ? sched : nil
            }), let cloze = clozeCards.first(where: { $0.sched != nil }) ?? clozeCards.first {
                cards.append(cloze)
                continue
            }
            if row.ord > 0 { continue }
            let front = CardImporter.clean(first)
            let back = row.fields.count > 1 ? CardImporter.clean(row.fields[1]) : ""
            guard !front.isEmpty, !back.isEmpty else { continue }
            cards.append(ParsedCard(front: front, back: back, tags: row.tags, sched: sched))
        }
        return cards.isEmpty ? nil : cards
    }

    private static func readLegacyNotes(_ db: OpaquePointer?) -> [ParsedCard]? {
        var stmt: OpaquePointer?
        // notes.flds = fields joined by the 0x1f unit separator; tags space-separated.
        guard sqlite3_prepare_v2(db, "SELECT flds, tags FROM notes", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var cards: [ParsedCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let fields = textColumn(stmt, 0).components(separatedBy: "\u{1f}")
            let tags = CardImporter.tagList(textColumn(stmt, 1))
            guard let first = fields.first else { continue }
            if let cloze = ClozeImporter.cards(from: first, tags: tags), !cloze.isEmpty {
                cards.append(contentsOf: cloze)
                continue
            }
            let front = CardImporter.clean(first)
            let back = fields.count > 1 ? CardImporter.clean(fields[1]) : ""
            guard !front.isEmpty, !back.isEmpty else { continue }
            cards.append(ParsedCard(front: front, back: back, tags: tags))
        }
        return cards.isEmpty ? nil : cards
    }

    private static func collectionCreatedDate(_ db: OpaquePointer?) -> Date {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT crt FROM col LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return .now }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return .now }
        let seconds = TimeInterval(sqlite3_column_int64(stmt, 0))
        guard seconds > 0 else { return .now }
        return Calendar.current.startOfDay(for: Date(timeIntervalSince1970: seconds))
    }

    private static func schedulingState(for row: AnkiCardRow, collectionCreated: Date) -> SchedulingState {
        let phase: CardPhase
        if row.queue < 0 {
            phase = row.reps > 0 ? .review : .new
        } else if row.type == 0 || row.queue == 0 || row.reps == 0 {
            phase = .new
        } else if row.type == 1 || row.queue == 1 || row.queue == 3 {
            phase = .learning
        } else if row.type == 3 {
            phase = .relearning
        } else {
            phase = .review
        }

        let due: Date
        if row.queue < 0 {
            due = .distantFuture
        } else if phase == .review {
            due = Calendar.current.date(byAdding: .day, value: row.due, to: collectionCreated) ?? .now
        } else if row.due > 1_000_000_000 {
            due = Date(timeIntervalSince1970: TimeInterval(row.due))
        } else {
            due = .now
        }

        let memory = memoryState(from: row)
        let lastReview = row.modified > 0 && row.reps > 0 ? Date(timeIntervalSince1970: TimeInterval(row.modified)) : nil
        return SchedulingState(
            memory: memory,
            phase: phase,
            due: due,
            lastReview: lastReview,
            reps: max(0, row.reps),
            lapses: max(0, row.lapses)
        )
    }

    private static func memoryState(from row: AnkiCardRow) -> MemoryState? {
        if let fsrs = fsrsMemoryState(from: row.data) {
            return fsrs
        }
        guard row.reps > 0 else { return nil }
        let stability = max(0.1, Double(max(1, row.interval)))
        let difficulty = difficultyFromAnkiEase(row.factor)
        return MemoryState(stability: stability, difficulty: difficulty)
    }

    private static func fsrsMemoryState(from data: String) -> MemoryState? {
        guard let json = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) else { return nil }
        guard let stability = findDouble(in: object, keys: ["s", "stability"]),
              let difficulty = findDouble(in: object, keys: ["d", "difficulty"]) else { return nil }
        return MemoryState(stability: max(0.01, stability), difficulty: min(10, max(1, difficulty)))
    }

    private static func findDouble(in object: Any, keys: Set<String>) -> Double? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if keys.contains(key.lowercased()) {
                    if let number = value as? NSNumber { return number.doubleValue }
                    if let string = value as? String, let number = Double(string) { return number }
                }
                if let nested = findDouble(in: value, keys: keys) { return nested }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = findDouble(in: value, keys: keys) { return nested }
            }
        }
        return nil
    }

    private static func difficultyFromAnkiEase(_ factor: Int) -> Double {
        guard factor > 0 else { return 5.0 }
        return min(10, max(1, 5.0 - (Double(factor) - 2500.0) / 300.0))
    }

    private static func textColumn(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
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
    let onImport: (_ deckName: String?, _ cards: [ParsedCard], _ source: String) -> Void

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
                    onImport(creatingNew ? newDeckName.trimmingCharacters(in: .whitespaces) : nil, parsed, "paste")
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
            onImport(name, cards, "anki")
        }
    }
}
