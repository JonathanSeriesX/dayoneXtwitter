// Produces journal-entry titles for tweets using a local LLM via Ollama —
// action phrases such as "Expressed frustration at airport security" or
// "Posted a meme about cats". Image attachments are shown to the model when
// it supports vision.

import Foundation

public final class OllamaClient {

    public struct Settings {
        public var host: String
        public var model: String
        public var timeout: TimeInterval
        public var maxImages: Int
        public var titlePrompt: String

        public init(host: String, model: String, timeout: TimeInterval,
                    maxImages: Int, titlePrompt: String) {
            self.host = host
            self.model = model
            self.timeout = timeout
            self.maxImages = maxImages
            self.titlePrompt = titlePrompt
        }

        public init(config: ImportConfig) {
            self.init(host: config.ollamaHost, model: config.ollamaModelName,
                      timeout: config.ollamaTimeout, maxImages: config.llmMaxImages,
                      titlePrompt: config.ollamaTitlePrompt)
        }
    }

    private let settings: Settings
    private let session: URLSession
    private let log: (String) -> Void

    /// Thinking models spend the whole token budget on the thought and return
    /// an empty answer, so thinking is switched off. Models that don't know the
    /// flag reject it outright; the first rejection flips this off and the
    /// title is retried.
    private var disableThinking = true

    public init(settings: Settings, log: @escaping (String) -> Void = { _ in }) {
        self.settings = settings
        self.log = log
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = settings.timeout
        configuration.timeoutIntervalForResource = settings.timeout
        self.session = URLSession(configuration: configuration)
    }

    /// The base URL of the Ollama server. Configs pointing at the
    /// /api/generate endpoint have that suffix trimmed off.
    private var resolvedHost: String {
        let host = settings.host
        if let range = host.range(of: "/api/") {
            return String(host[..<range.lowerBound])
        }
        return host.isEmpty ? "http://localhost:11434" : host
    }

    private static let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp"]

    /// Selects the image attachments to show the model alongside the tweet
    /// text; videos and missing files are skipped.
    ///
    /// Threads over the cap contribute a random sample rather than their first
    /// N images. Prompt-processing time scales with total pixel count — the
    /// archive's biggest thread, 26 full-size images, measured ~30k tokens and
    /// 80s of prefill on qwen3.5:9b-mlx, past the request timeout — and a photo
    /// dump's opening images are often near-duplicates, so taking the first N
    /// is both the slowest option and the least representative one. The sample
    /// is returned in thread order so the model still reads it as a sequence.
    func pickImages(_ mediaFiles: [String]) -> [String] {
        guard settings.maxImages > 0 else { return [] }
        let eligible = mediaFiles.filter { path in
            let lower = path.lowercased()
            return Self.imageExtensions.contains(where: { lower.hasSuffix($0) })
                && FileManager.default.fileExists(atPath: path)
        }
        guard eligible.count > settings.maxImages else { return eligible }
        return eligible.indices.shuffled()
            .prefix(settings.maxImages)
            .sorted()
            .map { eligible[$0] }
    }

    /// Cleans up a model-produced title; returns nil when the model declined
    /// ("Tweeted") or produced something that doesn't look like a title.
    static func normalizeTitle(_ raw: String) -> String? {
        var title = raw.pyStrip()
            .pyStrip(charactersIn: "\"“”'")
            .pyRstrip(charactersIn: ".")
            .pyStrip()
        title = title.pySplitlines().first?.pyStrip() ?? ""

        if title.isEmpty || title.lowercased() == "tweeted" { return nil }
        // A real title is a short phrase; anything longer is the model rambling.
        if title.count > 64 || title.split(whereSeparator: \.isWhitespace).count > 10 {
            return nil
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Produces a title for a tweet or thread, or nil when no confident title
    /// could be produced (the model answered "Tweeted", returned junk, or
    /// Ollama failed).
    public func generateTitle(entryText: String, mediaFiles: [String]) async -> String? {
        let prompt = "\(settings.titlePrompt)\n\nTweet: \(entryText)\nTitle:"
        let images = pickImages(mediaFiles)

        do {
            let raw = try await generate(prompt: prompt, images: images)
            return Self.normalizeTitle(raw)
        } catch let error as OllamaError {
            log("Warning: \(error.message)")
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost {
            log("Warning: Could not connect to Ollama at \(resolvedHost). Is the Ollama server running?")
        } catch {
            log("An unexpected error occurred during LLM summarization: \(error.localizedDescription)")
        }
        return nil
    }

    struct OllamaError: Error {
        let message: String
    }

    // MARK: - Server status (the Configure screen's Ollama row)

    /// One model the server has pulled, from /api/tags.
    public struct InstalledModel {
        public let name: String
        public let sizeBytes: Int64
        public let capabilities: [String]

        public var supportsVision: Bool { capabilities.contains("vision") }
    }

    /// The server's version, or a thrown error when it isn't reachable.
    public func serverVersion() async throws -> String {
        guard let url = URL(string: resolvedHost + "/api/version") else {
            throw OllamaError(message: "Malformed Ollama host: \(settings.host)")
        }
        let (data, _) = try await session.data(from: url)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["version"] as? String ?? ""
    }

    /// The models the server has pulled. Throws when the server is down —
    /// that's the signal the status row branches on.
    public func installedModels() async throws -> [InstalledModel] {
        guard let url = URL(string: resolvedHost + "/api/tags") else {
            throw OllamaError(message: "Malformed Ollama host: \(settings.host)")
        }
        let (data, _) = try await session.data(from: url)
        guard let models = Self.parseModels(data) else {
            throw OllamaError(message: "Unexpected /api/tags response shape.")
        }
        return models
    }

    static func parseModels(_ data: Data) -> [InstalledModel]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["models"] as? [[String: Any]]
        else { return nil }
        return list.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return InstalledModel(
                name: name,
                sizeBytes: (item["size"] as? NSNumber)?.int64Value ?? 0,
                capabilities: item["capabilities"] as? [String] ?? [])
        }
    }

    /// Finds the requested model among the installed ones, by Ollama's naming
    /// rule: names are case-insensitive and a missing tag means ":latest".
    public static func resolveModel(_ requested: String, in models: [InstalledModel]) -> InstalledModel? {
        let wanted = normalizeModelName(requested)
        return models.first { normalizeModelName($0.name) == wanted }
    }

    static func normalizeModelName(_ name: String) -> String {
        let trimmed = name.pyStrip().lowercased()
        return trimmed.contains(":") ? trimmed : trimmed + ":latest"
    }

    // MARK: - Pulling a model

    /// One line of /api/pull progress.
    public struct PullProgress {
        public let status: String
        /// completed/total of the layer being downloaded, when known.
        public let fraction: Double?
        public let completedBytes: Int64?
        public let totalBytes: Int64?
    }

    /// Parses one streamed /api/pull line. Returns nil for blank lines and
    /// noise, throws for a server-reported error, and flags the "success"
    /// line that ends the pull.
    static func parsePullLine(_ line: String) throws -> (progress: PullProgress, done: Bool)? {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if let error = json["error"] as? String {
            throw OllamaError(message: error)
        }
        let status = json["status"] as? String ?? ""
        var fraction: Double?
        var completed: Int64?
        var total: Int64?
        if let totalNumber = json["total"] as? NSNumber, totalNumber.int64Value > 0 {
            total = totalNumber.int64Value
            completed = (json["completed"] as? NSNumber)?.int64Value ?? 0
            fraction = Double(completed!) / Double(total!)
        }
        return (PullProgress(status: status, fraction: fraction,
                             completedBytes: completed, totalBytes: total),
                status == "success")
    }

    /// Downloads the configured model through the server (`ollama pull`),
    /// reporting progress line by line. Cancelling the surrounding Task stops
    /// the download; Ollama keeps the finished layers, so a retry resumes.
    public func pullModel(progress: @escaping (PullProgress) -> Void) async throws {
        guard let url = URL(string: resolvedHost + "/api/pull") else {
            throw OllamaError(message: "Malformed Ollama host: \(settings.host)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.model, "stream": true,
        ])
        // A pull can run for an hour; only stalls should time it out.
        request.timeoutInterval = 300

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        let pullSession = URLSession(configuration: configuration)

        let (bytes, _) = try await pullSession.bytes(for: request)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let parsed = try Self.parsePullLine(line) else { continue }
            progress(parsed.progress)
            if parsed.done { return }
        }
        throw OllamaError(message: "The download ended before the model was complete.")
    }

    /// Runs one completion, retrying without the thinking flag if the model
    /// doesn't support it.
    private func generate(prompt: String, images: [String]) async throws -> String {
        guard let url = URL(string: resolvedHost + "/api/generate") else {
            throw OllamaError(message: "Malformed Ollama host: \(settings.host)")
        }

        var body: [String: Any] = [
            "model": settings.model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_predict": 24,  // A title is a few words; don't let it ramble
                "temperature": 0.3,  // Keep it low for more deterministic output
                "num_ctx": 8192,  // Attached images consume context too
            ],
        ]
        if disableThinking {
            body["think"] = false
        }
        if !images.isEmpty {
            body["images"] = images.compactMap { path -> String? in
                (try? Data(contentsOf: URL(fileURLWithPath: path)))?.base64EncodedString()
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = settings.timeout

        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let serverMessage = json?["error"] as? String ?? "HTTP \(http.statusCode)"
            if disableThinking, serverMessage.lowercased().contains("does not support thinking") {
                disableThinking = false
                return try await generate(prompt: prompt, images: images)
            }
            throw OllamaError(
                message: "Ollama refused the request: \(serverMessage). "
                    + "Is the '\(settings.model)' model pulled?")
        }

        guard let text = json?["response"] as? String else {
            throw OllamaError(message: "Unexpected Ollama response shape.")
        }
        return text.pyStrip()
    }
}
