// The Configure screen's live Ollama status: is the server up, is the model
// pulled, what to do about it if not. Watches in the background while the
// LLM-titles section is visible — start Ollama or finish a download and the
// row flips green by itself, no button-mashing. Can also launch the app and
// pull the model right from the row.

import AppKit
import Foundation
import SwiftUI

@MainActor
final class OllamaStatusController: ObservableObject {

    /// How Ollama exists on this Mac, when the server isn't answering.
    enum Installation: Equatable {
        /// The menu-bar app — launching it starts the server.
        case app(URL)
        /// Just the CLI; the user has to `ollama serve` themselves.
        case cli(String)
        /// Nothing found — point at the download page.
        case notInstalled
        /// The host isn't this machine, so no local advice applies.
        case remote(String)
    }

    enum State: Equatable {
        case unknown
        case checking
        case ready(model: String, vision: Bool, version: String)
        case modelMissing(requested: String, installed: [String])
        case notRunning(Installation)
        case pulling(status: String, fraction: Double?, completed: Int64?, total: Int64?)
        case pullFailed(String)
    }

    @Published private(set) var state: State = .unknown

    private var pullTask: Task<Void, Never>?
    private var host = ""
    private var model = ""

    /// A client with a short timeout — a status probe must answer in a blink,
    /// not wait out the 120s the title requests are allowed.
    private static func probe(host: String, model: String) -> OllamaClient {
        OllamaClient(settings: .init(
            host: host, model: model, timeout: 4, maxImages: 0, titlePrompt: ""))
    }

    /// The watch loop, tied to the row's lifetime via .task(id:) — SwiftUI
    /// cancels it when the section disappears or host/model change, and a
    /// fresh loop starts with the new values. Re-checks forever: every few
    /// seconds while something is wrong (so installing/starting/pulling is
    /// noticed), more lazily once everything is green.
    func watch(host: String, model: String) async {
        self.host = host
        self.model = model
        // Debounce: every keystroke in the host/model fields restarts this.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }

        if state == .unknown { state = .checking }
        while !Task.isCancelled {
            // The pull owns the state while it runs.
            if pullTask == nil, !isPullingOrFailed {
                await checkOnce()
            }
            let interval: UInt64 = {
                if case .ready = state { return 8_000_000_000 }
                return 3_000_000_000
            }()
            do { try await Task.sleep(nanoseconds: interval) } catch { break }
        }
    }

    private var isPullingOrFailed: Bool {
        switch state {
        case .pulling, .pullFailed: return true
        default: return false
        }
    }

    private func checkOnce() async {
        let probe = Self.probe(host: host, model: model)
        let requested = model
        do {
            let models = try await probe.installedModels()
            guard !Task.isCancelled else { return }
            if let match = OllamaClient.resolveModel(requested, in: models) {
                let version = (try? await probe.serverVersion()) ?? ""
                state = .ready(model: match.name, vision: match.supportsVision, version: version)
            } else {
                state = .modelMissing(requested: requested, installed: models.map(\.name))
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .notRunning(Self.findInstallation(host: host))
        }
    }

    /// What "not running" should suggest: launch the app, run the CLI, or
    /// install — all local-only advice, so a remote host short-circuits.
    static func findInstallation(host: String) -> Installation {
        let serverHost = URL(string: host)?.host?.lowercased()
        let localHosts: Set<String?> = [nil, "localhost", "127.0.0.1", "0.0.0.0", "::1"]
        guard localHosts.contains(serverHost) else {
            return .remote(host)
        }

        let fm = FileManager.default
        let appCandidates = [
            "/Applications/Ollama.app",
            ("~/Applications/Ollama.app" as NSString).expandingTildeInPath,
        ]
        for path in appCandidates where fm.fileExists(atPath: path) {
            return .app(URL(fileURLWithPath: path))
        }
        for path in ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
        where fm.fileExists(atPath: path) {
            return .cli(path)
        }
        return .notInstalled
    }

    /// Launches the Ollama app; the watch loop notices the server coming up.
    func launchApp() {
        guard case .notRunning(.app(let url)) = state else { return }
        state = .checking
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    /// Pulls the configured model through the server, with live progress.
    /// Cancelling keeps the finished layers — Ollama resumes on the next try.
    func pull() {
        guard pullTask == nil else { return }
        state = .pulling(status: "Contacting the server…", fraction: nil,
                         completed: nil, total: nil)
        let client = Self.probe(host: host, model: model)

        pullTask = Task { [weak self] in
            do {
                try await client.pullModel { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .pulling = self.state else { return }
                        self.state = .pulling(
                            status: progress.status, fraction: progress.fraction,
                            completed: progress.completedBytes, total: progress.totalBytes)
                    }
                }
                await MainActor.run { [weak self] in self?.state = .unknown }
            } catch is CancellationError {
                await MainActor.run { [weak self] in self?.state = .unknown }
            } catch let error as OllamaClient.OllamaError {
                await MainActor.run { [weak self] in self?.state = .pullFailed(error.message) }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .pullFailed(error.localizedDescription)
                }
            }
            await MainActor.run { [weak self] in
                self?.pullTask = nil
                if case .unknown = self?.state { Task { await self?.checkOnce() } }
            }
        }
    }

    func cancelPull() {
        pullTask?.cancel()
    }

    /// Clears a failed download so the watch loop takes over again.
    func dismissFailure() {
        if case .pullFailed = state { state = .unknown }
    }
}
