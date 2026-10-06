import Testing
import Foundation
@testable import Plainfile

struct DelimitedTextTests {

    @Test func parsesQuotedFieldsAndEmbeddedNewlines() {
        let csv = "name,note\n\"Smith, John\",\"line one\nline two\"\nJane,\"She said \"\"hi\"\"\"\n"
        let table = DelimitedText.parse(csv, delimiter: ",", hasHeaderRow: true)
        #expect(table.columns == ["name", "note"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0].cells == ["Smith, John", "line one\nline two"])
        #expect(table.rows[1].cells == ["Jane", "She said \"hi\""])
    }

    @Test func roundTripsThroughSerializer() {
        let csv = "a,b,c\n1,\"x,y\",3\n4,5,\"multi\nline\"\n"
        let table = DelimitedText.parse(csv, delimiter: ",", hasHeaderRow: true)
        let out = DelimitedText.serialize(table)
        #expect(out == csv)
    }

    @Test func handlesCRLFAndTabs() {
        let tsv = "a\tb\r\n1\t2\r\n"
        let table = DelimitedText.parse(tsv, delimiter: "\t", hasHeaderRow: true)
        #expect(table.columns == ["a", "b"])
        #expect(table.rows.first?.cells == ["1", "2"])
    }

    @Test func detectsDelimiter() {
        #expect(DelimitedText.detectDelimiter(in: "a;b;c\n1;2;3\n") == ";")
        #expect(DelimitedText.detectDelimiter(in: "a\tb\tc\n1\t2\t3\n") == "\t")
        #expect(DelimitedText.detectDelimiter(in: "a,b,c\n1,2,3\n") == ",")
    }

    @Test func padsRaggedRows() {
        let table = DelimitedText.parse("a,b,c\n1\n", delimiter: ",", hasHeaderRow: true)
        #expect(table.rows[0].cells == ["1", "", ""])
    }

    @Test func numericAwareSorting() {
        let c = CellComparator(column: 0)
        #expect(c.compare(DataRow(cells: ["9"]), DataRow(cells: ["10"])) == .orderedAscending)
        #expect(c.compare(DataRow(cells: ["b"]), DataRow(cells: ["a"])) == .orderedDescending)
        #expect(c.compare(DataRow(cells: [""]), DataRow(cells: ["a"])) == .orderedDescending)
    }

    // MARK: Source ranges

    private func texts(_ csv: String, delimiter: Character = ",") -> [[String]] {
        let ns = csv as NSString
        return DelimitedText.recordRanges(csv, delimiter: delimiter).map { record in
            [ns.substring(with: record.range)] + record.fields.map { ns.substring(with: $0) }
        }
    }

    @Test func recordRangesCoverEachLineAndField() {
        let csv = "a,b\n1,22\n"
        #expect(texts(csv) == [["a,b", "a", "b"], ["1,22", "1", "22"]])
    }

    @Test func recordRangesKeepQuotedFieldsWhole() {
        let csv = "name,note\n\"Smith, John\",\"line one\nline two\"\nJane,\"say \"\"hi\"\"\"\n"
        let records = texts(csv)
        #expect(records.count == 3)
        #expect(records[1] == ["\"Smith, John\",\"line one\nline two\"", "\"Smith, John\"", "\"line one\nline two\""])
        #expect(records[2][2] == "\"say \"\"hi\"\"\"")
    }

    @Test func recordRangesMatchTheParsedRecords() {
        let samples = ["a,b\r\n1,2\r\n", "x;y\n1;2", "only\n\n\nlast", "\"\"\n", "a,\"b\nc\"\n\n"]
        for csv in samples {
            let delimiter: Character = csv.contains(";") ? ";" : ","
            #expect(DelimitedText.recordRanges(csv, delimiter: delimiter).map(\.fields.count) == DelimitedText.parseRecords(csv, delimiter: delimiter).map(\.count), "\(csv.debugDescription)")
        }
    }

    @Test func recordRangesHandleMultiByteText() {
        let csv = "emoji,name\n👋,Zoë\n"
        #expect(texts(csv)[1] == ["👋,Zoë", "👋", "Zoë"])
    }

    @MainActor @Test func tableModelMapsRowsToSourceAndBack() {
        let csv = "name,qty\nApple,3\nPear,12\nPlum,7\n"
        let model = TableModel(table: DelimitedText.parse(csv, delimiter: ",", hasHeaderRow: true))
        model.updateSourceRanges(for: csv)
        let ns = csv as NSString
        let pear = model.table.rows[1].id
        let plum = model.table.rows[2].id
        #expect(model.sourceRanges(forRows: [pear, plum]).map { ns.substring(with: $0) } == ["Pear,12\nPlum,7"])
        #expect(model.sourceRanges(forRows: [model.table.rows[0].id, plum]).count == 2)
        #expect(model.rowIDs(touching: [ns.range(of: "12")]) == [pear])
        // A caret at the end of a line belongs to that line.
        #expect(model.rowIDs(touching: [NSRange(location: ns.range(of: "Pear,12").upperBound, length: 0)]) == [pear])
        #expect(model.rowIDs(touching: [ns.range(of: "name")]).isEmpty)
        #expect(model.sourceRange(forCell: plum, column: 1).map { ns.substring(with: $0) } == "7")
    }
}
