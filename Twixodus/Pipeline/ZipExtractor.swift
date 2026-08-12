// Handles a dropped twitter-*.zip: extracts it into a folder next to the zip
// (Twitter's export has data/ and assets/ at the top level, so the folder is
// named after the zip) and hands back the folder, which the rest of the app
// treats exactly like a dropped folder.

import Foundation

public enum ZipExtractor {

    public enum ZipError: LocalizedError {
        case extractionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .extractionFailed(let details):
                return "Couldn't extract the archive: \(details)"
            }
        }
    }

    public static func isZip(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// The folder the zip extracts into: same name, next to the zip.
    public static func destination(for zipURL: URL) -> URL {
        zipURL.deletingPathExtension()
    }

    /// Extracts the zip next to itself and returns the folder. If the folder
    /// already exists and holds a readable archive, extraction is skipped —
    /// dropping the same zip twice shouldn't unpack 2.5 GB twice.
    public static func extract(_ zipURL: URL) throws -> URL {
        let dest = destination(for: zipURL)

        if (try? TwitterArchiveLoader.findArchive(at: dest)) != nil {
            return dest
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, dest.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw ZipError.extractionFailed(error.localizedDescription)
        }
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: errData, encoding: .utf8) ?? ""
            throw ZipError.extractionFailed(
                details.isEmpty ? "ditto exited with \(process.terminationStatus)" : details)
        }
        return dest
    }
}
