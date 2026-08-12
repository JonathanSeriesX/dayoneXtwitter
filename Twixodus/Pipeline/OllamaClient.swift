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

    /// Selects up to maxImages existing image attachments (videos and missing
    /// files are skipped) to show the model alongside the tweet text.
    func pickImages(_ mediaFiles: [String]) -> [String] {
        var images: [String] = []
        for path in mediaFiles {
            if images.count >= settings.maxImages { break }
            let lower = path.lowercased()
            if Self.imageExtensions.contains(where: { lower.hasSuffix($0) }),
               FileManager.default.fileExists(atPath: path) {
                images.append(path)
            }
        }
        return images
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
