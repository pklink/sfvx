// sfv/ContentView.swift
import SwiftUI
import zlib
import UniformTypeIdentifiers

struct DroppedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let crc32: UInt32
    var expectedCRC32: UInt32?
    var status: VerificationStatus {
        guard let expected = expectedCRC32 else { return .notChecked }
        return crc32 == expected ? .match : .mismatch
    }
}

enum VerificationStatus: String {
    case notChecked = "Not Checked"
    case match = "Match"
    case mismatch = "Mismatch"
}

struct ContentView: View {
    @State private var droppedFiles: [DroppedFile] = []
    @State private var showFileList: Bool = false

    func crc32Hash(for url: URL) -> UInt32? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return UInt32(crc32(0, baseAddress.assumingMemoryBound(to: Bytef.self), uInt(buffer.count)))
        }
    }

    func handleDrop(urls: [URL]) {
        var sfvMap: [String: UInt32]? = nil
        if let sfvURL = urls.first(where: { $0.pathExtension.lowercased() == "sfv" }) {
            sfvMap = SFVManager.parseSFV(sfvURL)
        }
        let fileURLs = urls.filter { $0.pathExtension.lowercased() != "sfv" }
        var files: [DroppedFile] = []
        for url in fileURLs {
            if let hash = crc32Hash(for: url) {
                let expected = sfvMap?[url.lastPathComponent]
                files.append(DroppedFile(url: url, crc32: hash, expectedCRC32: expected))
            }
        }
        droppedFiles = files
        showFileList = true
    }

    var body: some View {
        VStack {
            if showFileList {
                List(droppedFiles) { file in
                    VStack(alignment: .leading) {
                        Text(file.url.lastPathComponent)
                        Text(String(format: "CRC32: %08X", file.crc32))
                            .font(.caption)
                        if let expected = file.expectedCRC32 {
                            Text("Expected: \(String(format: "%08X", expected))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text("Status: \(file.status.rawValue)")
                                .font(.caption2)
                                .foregroundColor(file.status == .match ? .green : .red)
                        }
                    }
                }
                // Summary Section
                let totalFiles = droppedFiles.count
                let successful = droppedFiles.filter { $0.status == .match }.count
                let failed = droppedFiles.filter { $0.status == .mismatch }.count
                HStack {
                    Text("Total files: \(totalFiles)")
                    Spacer()
                    Text("Successful: \(successful)").foregroundColor(.green)
                    Spacer()
                    Text("Failed: \(failed)").foregroundColor(.red)
                }
                .padding(.vertical)
                HStack {
                    Button("Save SFV") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [UTType(filenameExtension: "sfv")!]
                        panel.nameFieldStringValue = "files.sfv"
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            try? SFVManager.saveSFV(droppedFiles, to: url)
                        }
                    }
                    .padding(.top)
                    Spacer()
                    Button("Clear") {
                        droppedFiles = []
                        showFileList = false
                    }
                    .padding(.top)
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0))
                    .overlay(Text("Drop files or SFV here").foregroundColor(.gray))
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        var urls: [URL] = []
                        let group = DispatchGroup()
                        for provider in providers {
                            group.enter()
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                if let url = url { urls.append(url) }
                                group.leave()
                            }
                        }
                        group.notify(queue: .main) {
                            handleDrop(urls: urls)
                        }
                        return true
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
