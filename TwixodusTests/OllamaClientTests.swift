import XCTest

final class OllamaClientTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OllamaClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Creates real files on disk — pickImages skips attachments that are gone.
    private func makeFiles(_ names: [String]) -> [String] {
        names.map { name in
            let url = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url.path
        }
    }

    private func client(maxImages: Int) -> OllamaClient {
        OllamaClient(settings: .init(
            host: "http://localhost:11434", model: "test", timeout: 120,
            maxImages: maxImages, titlePrompt: "prompt"))
    }

    func testKeepsEveryImageWhenUnderTheCap() {
        let files = makeFiles((0..<7).map { "img\($0).jpg" })
        XCTAssertEqual(client(maxImages: 10).pickImages(files), files)
    }

    func testSkipsVideosAndMissingFiles() {
        let present = makeFiles(["a.jpg", "clip.mp4", "b.PNG"])
        let missing = directory.appendingPathComponent("gone.jpg").path
        let picked = client(maxImages: 10).pickImages(present + [missing])
        XCTAssertEqual(picked, [present[0], present[2]])
    }

    func testZeroCapDisablesVision() {
        let files = makeFiles(["a.jpg", "b.jpg"])
        XCTAssertEqual(client(maxImages: 0).pickImages(files), [])
    }

    func testSamplesDownToTheCapWithoutDuplicates() {
        let files = makeFiles((0..<26).map { "img\($0).jpg" })
        let picked = client(maxImages: 10).pickImages(files)

        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(Set(picked).count, 10, "sample must not repeat an image")
        XCTAssertTrue(Set(picked).isSubset(of: Set(files)))
    }

    func testSampleStaysInThreadOrder() {
        let files = makeFiles((0..<26).map { "img\($0).jpg" })
        let picked = client(maxImages: 10).pickImages(files)
        let positions = picked.map { files.firstIndex(of: $0)! }
        XCTAssertEqual(positions, positions.sorted())
    }

    /// The point of sampling is that it isn't "the first ten every time".
    func testSampleVariesBetweenCalls() {
        let files = makeFiles((0..<26).map { "img\($0).jpg" })
        let subject = client(maxImages: 10)
        let seen = Set((0..<50).map { _ in subject.pickImages(files).joined(separator: ",") })
        XCTAssertGreaterThan(seen.count, 1, "selection should not be deterministic")
    }
    // MARK: - Server status parsing (the Configure screen's Ollama row)

    func testParseModelsReadsNamesSizesAndCapabilities() {
        let json = """
        {"models":[
          {"name":"qwen3.5:9b-mlx","size":8903014758,
           "capabilities":["completion","vision","thinking"]},
          {"name":"qwen3:8b","size":5225388164,"capabilities":["completion"]}
        ]}
        """.data(using: .utf8)!
        let models = OllamaClient.parseModels(json)!
        XCTAssertEqual(models.map(\.name), ["qwen3.5:9b-mlx", "qwen3:8b"])
        XCTAssertEqual(models[0].sizeBytes, 8_903_014_758)
        XCTAssertTrue(models[0].supportsVision)
        XCTAssertFalse(models[1].supportsVision)
    }

    func testParseModelsRejectsUnexpectedShape() {
        XCTAssertNil(OllamaClient.parseModels(Data("not json".utf8)))
        XCTAssertNil(OllamaClient.parseModels(Data("{}".utf8)))
    }

    func testResolveModelNormalizesTagAndCase() {
        let models = [
            OllamaClient.InstalledModel(name: "qwen3.5:9b-mlx", sizeBytes: 0, capabilities: []),
            OllamaClient.InstalledModel(name: "llama3:latest", sizeBytes: 0, capabilities: []),
        ]
        // Exact, case-insensitive, and the ":latest is implied" rule.
        XCTAssertNotNil(OllamaClient.resolveModel("qwen3.5:9b-mlx", in: models))
        XCTAssertNotNil(OllamaClient.resolveModel("QWEN3.5:9B-MLX", in: models))
        XCTAssertNotNil(OllamaClient.resolveModel("llama3", in: models))
        XCTAssertNotNil(OllamaClient.resolveModel(" llama3:latest ", in: models))
        XCTAssertNil(OllamaClient.resolveModel("qwen3.5", in: models),
                     "no tag means :latest, which isn't the -mlx build")
        XCTAssertNil(OllamaClient.resolveModel("mistral", in: models))
    }

    func testParsePullLineProgressErrorAndSuccess() throws {
        let progress = try OllamaClient.parsePullLine(
            #"{"status":"pulling 203e300","digest":"sha256:x","total":1000,"completed":250}"#)!
        XCTAssertEqual(progress.progress.status, "pulling 203e300")
        XCTAssertEqual(progress.progress.fraction!, 0.25, accuracy: 0.001)
        XCTAssertEqual(progress.progress.totalBytes, 1000)
        XCTAssertFalse(progress.done)

        let manifest = try OllamaClient.parsePullLine(#"{"status":"pulling manifest"}"#)!
        XCTAssertNil(manifest.progress.fraction)
        XCTAssertFalse(manifest.done)

        let success = try OllamaClient.parsePullLine(#"{"status":"success"}"#)!
        XCTAssertTrue(success.done)

        XCTAssertNil(try OllamaClient.parsePullLine(""))
        XCTAssertThrowsError(try OllamaClient.parsePullLine(
            #"{"error":"pull model manifest: file does not exist"}"#))
    }

}
