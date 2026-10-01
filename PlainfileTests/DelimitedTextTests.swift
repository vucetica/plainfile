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
}
