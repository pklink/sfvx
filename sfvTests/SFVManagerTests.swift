import XCTest
@testable import sfv

class SFVManagerTests: XCTestCase {
    func testParseSFV() {
        // Prepare a sample SFV content
        let sfvString = "file1.txt 12345678\nfile2.txt ABCDEF12"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.sfv")
        try? sfvString.write(to: tempURL, atomically: true, encoding: .utf8)
        
        let result = SFVManager.parseSFV(tempURL)
        XCTAssertEqual(result?["file1.txt"], 0x12345678)
        XCTAssertEqual(result?["file2.txt"], 0xABCDEF12)
    }

    func testSaveSFV() throws {
        let files = [
            DroppedFile(url: URL(fileURLWithPath: "/tmp/file1.txt"), crc32: 0x12345678, expectedCRC32: nil),
            DroppedFile(url: URL(fileURLWithPath: "/tmp/file2.txt"), crc32: 0xABCDEF12, expectedCRC32: nil)
        ]
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("output.sfv")
        try SFVManager.saveSFV(files, to: tempURL)
        let saved = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(saved.contains("file1.txt 12345678"))
        XCTAssertTrue(saved.contains("file2.txt ABCDEF12"))
    }
}
