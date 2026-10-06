import Foundation

nonisolated struct DataRow: Identifiable, Sendable, Hashable {
    let id: UUID
    var cells: [String]

    init(id: UUID = UUID(), cells: [String]) {
        self.id = id
        self.cells = cells
    }
}

/// In-memory model of a CSV / TSV file.
nonisolated struct DelimitedTable: Sendable, Equatable {
    var columns: [String]
    var rows: [DataRow]
    var delimiter: Character
    var hasHeaderRow: Bool

    var columnCount: Int { columns.count }

    subscript(row rowID: UUID, column column: Int) -> String {
        get {
            guard let r = rows.first(where: { $0.id == rowID }), column < r.cells.count else { return "" }
            return r.cells[column]
        }
    }

    mutating func normalize() {
        let width = max(columns.count, rows.map(\.cells.count).max() ?? 0)
        while columns.count < width { columns.append("Column \(columns.count + 1)") }
        for i in rows.indices where rows[i].cells.count < width {
            rows[i].cells.append(contentsOf: Array(repeating: "", count: width - rows[i].cells.count))
        }
    }

    static func empty(delimiter: Character = ",") -> DelimitedTable {
        DelimitedTable(columns: ["Column 1", "Column 2", "Column 3"], rows: [DataRow(cells: ["", "", ""])], delimiter: delimiter, hasHeaderRow: true)
    }
}

nonisolated enum DelimitedText {

    /// Picks the delimiter that appears most consistently across the first lines.
    static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        let lines = text.split(separator: "\n", maxSplits: 20, omittingEmptySubsequences: true).prefix(20)
        guard !lines.isEmpty else { return "," }
        var best: Character = ","
        var bestScore = -1.0
        for candidate in candidates {
            var counts: [Int] = []
            for line in lines {
                counts.append(line.reduce(0) { $0 + ($1 == candidate ? 1 : 0) })
            }
            let nonZero = counts.filter { $0 > 0 }
            guard !nonZero.isEmpty else { continue }
            let mean = Double(nonZero.reduce(0, +)) / Double(nonZero.count)
            let variance = nonZero.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(nonZero.count)
            // Prefer delimiters that appear on most lines with a stable count.
            let coverage = Double(nonZero.count) / Double(lines.count)
            let score = coverage * mean / (1 + variance)
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    /// RFC 4180 style parser. Handles quoted fields, escaped quotes, embedded newlines and CRLF.
    static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        var sawAnything = false
        let quote: Unicode.Scalar = "\""
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"
        let delimiterScalar = delimiter.unicodeScalars.first ?? ","

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        func endField() {
            record.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRecord() {
            endField()
            records.append(record)
            record = []
        }

        while let c = next() {
            sawAnything = true
            if inQuotes {
                if c == quote {
                    if let n = next() {
                        if n == quote {
                            field.append(quote)
                        } else {
                            inQuotes = false
                            pending = n
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            if c == quote {
                if field.isEmpty {
                    inQuotes = true
                } else {
                    field.append(c)
                }
            } else if c == delimiterScalar {
                endField()
            } else if c == lf {
                endRecord()
            } else if c == cr {
                if let n = next(), n != lf { pending = n }
                endRecord()
            } else {
                field.append(c)
            }
        }
        if sawAnything, !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return records
    }

    static func parse(_ text: String, delimiter: Character, hasHeaderRow: Bool) -> DelimitedTable {
        var records = parseRecords(text, delimiter: delimiter)
        // Drop trailing completely empty records produced by blank lines at the end.
        while let last = records.last, last.allSatisfy(\.isEmpty), records.count > 1 { records.removeLast() }
        var columns: [String] = []
        if hasHeaderRow, !records.isEmpty {
            columns = records.removeFirst()
        }
        var table = DelimitedTable(columns: columns, rows: records.map { DataRow(cells: $0) }, delimiter: delimiter, hasHeaderRow: hasHeaderRow)
        if table.columns.isEmpty, table.rows.isEmpty {
            table = .empty(delimiter: delimiter)
            table.hasHeaderRow = hasHeaderRow
        }
        table.normalize()
        return table
    }

    static func escape(_ field: String, delimiter: Character) -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r") || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Tab-separated text in the form Excel and Google Sheets paste into separate
    /// cells. A field that holds a tab, a line break or a quote is quoted, with its
    /// quotes doubled, so it still lands in one cell.
    static func clipboardText(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains("\t") || field.contains("\n") || field.contains("\r") || field.contains("\"")
                guard needsQuotes else { return field }
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// An HTML table of the same cells. Google Docs pastes it as a table, and
    /// spreadsheets use it to keep line breaks inside a cell. `header` becomes a row
    /// of `<th>` cells.
    static func clipboardHTML(_ rows: [[String]], header: [String]? = nil) -> String {
        func cell(_ tag: String, _ text: String) -> String {
            let escaped = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\r\n", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
                .replacingOccurrences(of: "\r", with: "<br>")
            return "<\(tag)>\(escaped)</\(tag)>"
        }
        var html = "<meta charset=\"utf-8\"><table>"
        if let header {
            html += "<tr>" + header.map { cell("th", $0) }.joined() + "</tr>"
        }
        for row in rows {
            html += "<tr>" + row.map { cell("td", $0) }.joined() + "</tr>"
        }
        return html + "</table>"
    }

    static func serialize(_ table: DelimitedTable) -> String {
        let d = String(table.delimiter)
        var lines: [String] = []
        lines.reserveCapacity(table.rows.count + 1)
        if table.hasHeaderRow {
            lines.append(table.columns.map { escape($0, delimiter: table.delimiter) }.joined(separator: d))
        }
        for row in table.rows {
            lines.append(row.cells.map { escape($0, delimiter: table.delimiter) }.joined(separator: d))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
