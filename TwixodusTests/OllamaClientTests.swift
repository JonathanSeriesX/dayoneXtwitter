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
}
