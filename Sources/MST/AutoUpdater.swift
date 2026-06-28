import AppKit
import Foundation

private let githubOwner = "ducky8x"
private let githubRepo = "Mac-Speedrunning-Tools"

@MainActor
final class AutoUpdater: ObservableObject {
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, asset: URL)
        case downloading(progress: Double?)
        case installing
        case failed(String)

        var isActionable: Bool {
            switch self {
            case .available, .downloading, .installing, .failed: true
            default: false
            }
        }
    }

    @Published var updateState: UpdateState = .idle

    func checkOnLaunch() {
        Task { await check() }
    }

    func startUpdate() {
        guard case .available(_, let url) = updateState else { return }
        Task { await downloadAndInstall(from: url) }
    }

    func retry() {
        checkOnLaunch()
    }

    // MARK: - Check

    private func check() async {
        updateState = .checking

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let apiURL = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]]
        else {
            updateState = .idle
            return
        }

        let remote = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(remote, than: current) else {
            updateState = .upToDate
            return
        }

        let asset = assets.first { a in
            guard let name = a["name"] as? String else { return false }
            let lower = name.lowercased()
            return lower.hasSuffix(".zip") && (lower.contains("macos") || lower == "mst.zip")
        }

        guard let asset,
              let urlString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString)
        else {
            updateState = .idle
            return
        }

        updateState = .available(version: remote, asset: downloadURL)
    }

    // MARK: - Download & Install

    private func downloadAndInstall(from url: URL) async {
        updateState = .downloading(progress: nil)

        guard let (tmpFile, _) = try? await URLSession.shared.download(from: url) else {
            updateState = .failed("Download failed. Check your internet connection.")
            return
        }

        updateState = .installing

        do {
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MSTExtract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let exitCode = try await runProcess(
                URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-q", tmpFile.path, "-d", extractDir.path]
            )
            guard exitCode == 0 else {
                throw NSError(domain: "AutoUpdater", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to unzip the downloaded update."])
            }

            let newApp = try findApp(in: extractDir)
            let currentApp = Bundle.main.bundleURL

            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("MST_staged_\(UUID().uuidString).app")
            try FileManager.default.copyItem(at: newApp, to: staged)

            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mst_swap_\(UUID().uuidString).sh")
            try swapScript(staged: staged.path, target: currentApp.path)
                .write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let bash = Process()
            bash.executableURL = URL(fileURLWithPath: "/bin/bash")
            bash.arguments = [scriptURL.path]
            try bash.run()

            NSApp.terminate(nil)
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func findApp(in dir: URL) throws -> URL {
        func search(in url: URL, depth: Int) -> URL? {
            guard depth >= 0,
                  let items = try? FileManager.default.contentsOfDirectory(
                      at: url,
                      includingPropertiesForKeys: [.isDirectoryKey],
                      options: .skipsHiddenFiles
                  )
            else { return nil }
            for item in items {
                if item.pathExtension == "app" { return item }
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDir, let found = search(in: item, depth: depth - 1) { return found }
            }
            return nil
        }
        guard let app = search(in: dir, depth: 3) else {
            throw NSError(
                domain: "AutoUpdater", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "MST.app not found inside the downloaded zip."]
            )
        }
        return app
    }

    private func swapScript(staged: String, target: String) -> String {
        """
        #!/bin/bash
        set -e
        # Wait for MST to fully exit
        while pgrep -xq "MST" 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        # Replace the app bundle
        rm -rf '\(target)'
        cp -R '\(staged)' '\(target)'
        # Clear quarantine so macOS doesn't block the new binary
        xattr -cr '\(target)' 2>/dev/null || true
        # Relaunch
        open '\(target)'
        # Clean up
        rm -rf '\(staged)'
        rm -- "$0"
        """
    }

    private func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let n = max(r.count, c.count)
        for i in 0..<n {
            let ri = i < r.count ? r[i] : 0
            let ci = i < c.count ? c[i] : 0
            if ri > ci { return true }
            if ri < ci { return false }
        }
        return false
    }
}

// Runs a process off the main thread and returns its exit code.
private func runProcess(_ url: URL, arguments: [String]) async throws -> Int32 {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = url
            proc.arguments = arguments
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                continuation.resume(returning: proc.terminationStatus)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
