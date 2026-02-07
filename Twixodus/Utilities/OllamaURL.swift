import Foundation

func normalizedOllamaGenerateURL(from raw: String) -> URL? {
    guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return nil
    }
    guard components.scheme != nil, components.host != nil else {
        return nil
    }

    let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty || path == "/" || path == "/api" {
        components.path = "/api/generate"
    }

    return components.url
}
