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
    @State private var isCalculating: Bool = false
    @State private var calculationProgress: Double = 0.0
    @State private var showLoadingIndicator: Bool = false
    @State private var lastDropFirstFileDirectory: URL? = nil
    @State private var saveShortcutMonitor: Any? = nil
    @State private var isDropTargeted: Bool = false

    func crc32Hash(for url: URL) -> UInt32? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return UInt32(crc32(0, baseAddress.assumingMemoryBound(to: Bytef.self), uInt(buffer.count)))
        }
    }

    func handleDrop(urls: [URL]) {
        isCalculating = true
        calculationProgress = 0.0
        showLoadingIndicator = true
        // Store the directory of the first file in the last drop
        if let firstFile = urls.first(where: { $0.pathExtension.lowercased() != "sfv" }) {
            lastDropFirstFileDirectory = firstFile.deletingLastPathComponent()
        } else {
            lastDropFirstFileDirectory = nil
        }
        // Minimum loading indicator duration (e.g. 0.5 seconds)
        let minIndicatorTime: TimeInterval = 0.5
        let startTime = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            var sfvMap: [String: UInt32]? = nil
            if let sfvURL = urls.first(where: { $0.pathExtension.lowercased() == "sfv" }) {
                sfvMap = SFVManager.parseSFV(sfvURL)
            }
            let fileURLs = urls.filter { $0.pathExtension.lowercased() != "sfv" }
            var files: [DroppedFile] = []
            let total = fileURLs.count
            for (index, url) in fileURLs.enumerated() {
                if let hash = crc32Hash(for: url) {
                    let expected = sfvMap?[url.lastPathComponent]
                    files.append(DroppedFile(url: url, crc32: hash, expectedCRC32: expected))
                }
                let progress = Double(index + 1) / Double(max(total, 1))
                DispatchQueue.main.async {
                    calculationProgress = progress
                }
            }
            let elapsed = Date().timeIntervalSince(startTime)
            let delay = max(0, minIndicatorTime - elapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                droppedFiles = files
                showFileList = true
                isCalculating = false
                calculationProgress = 0.0
                showLoadingIndicator = false
            }
        }
    }

    var body: some View {
        VStack {
            if showLoadingIndicator || isCalculating {
                VStack {
                    ProgressView("Calculating checksums...", value: calculationProgress, total: 1.0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(String(format: "%.0f%%", calculationProgress * 100))
                        .font(.caption)
                        .padding(.top, 4)
                }
            } else if showFileList {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
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
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
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
                        panel.nameFieldStringValue = "checksums.sfv"
                        panel.canCreateDirectories = true
                        if let defaultDirectory = lastDropFirstFileDirectory {
                            panel.directoryURL = defaultDirectory
                        }
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
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.04))
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                    .overlay(Text("Drop files or SFV here").foregroundColor(.gray))
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
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
        .onAppear {
            addSaveShortcut()
        }
        .onChange(of: showFileList) { newValue in
            updateSaveShortcutMonitor(enabled: newValue)
        }
    }

    private func addSaveShortcut() {
        updateSaveShortcutMonitor(enabled: showFileList)
    }

    private func updateSaveShortcutMonitor(enabled: Bool) {
        #if os(macOS)
        if enabled {
            if saveShortcutMonitor == nil {
                saveShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                        saveSFV()
                        return nil
                    }
                    return event
                }
            }
        } else {
            if let monitor = saveShortcutMonitor {
                NSEvent.removeMonitor(monitor)
                saveShortcutMonitor = nil
            }
        }
        #endif
    }

    private func saveSFV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sfv")!]
        panel.nameFieldStringValue = "checksums.sfv"
        panel.canCreateDirectories = true
        if let defaultDirectory = lastDropFirstFileDirectory {
            panel.directoryURL = defaultDirectory
        }
        if panel.runModal() == .OK, let url = panel.url {
            try? SFVManager.saveSFV(droppedFiles, to: url)
        }
    }
}
