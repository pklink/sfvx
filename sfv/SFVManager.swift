import Foundation

class SFVManager {
    static func parseSFV(_ url: URL) -> [String: UInt32]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var result: [String: UInt32] = [:]
        for line in content.split(whereSeparator: \.isNewline) {
            let lineStr = String(line)
            guard let lastSpace = lineStr.lastIndex(of: " ") else { continue }
            let filename = String(lineStr[..<lastSpace])
            let crcStr = String(lineStr[lineStr.index(after: lastSpace)...])
            if let crc = UInt32(crcStr, radix: 16) {
                result[filename] = crc
            }
        }
        return result
    }

    static func saveSFV(_ files: [DroppedFile], to url: URL) throws {
        let sfvContent = files.map { file in
            "\(file.url.lastPathComponent) \(String(format: "%08X", file.crc32))"
        }.joined(separator: "\n")
        try sfvContent.write(to: url, atomically: true, encoding: .utf8)
    }
}
