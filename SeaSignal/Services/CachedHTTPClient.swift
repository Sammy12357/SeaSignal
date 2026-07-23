import CryptoKit
import Foundation

struct CachedHTTPResponse: Sendable {
    let data: Data
    let fetchedAt: Date
    let isStale: Bool
}

actor CachedHTTPClient {
    static let shared = CachedHTTPClient()

    private struct Entry: Codable {
        let data: Data
        let fetchedAt: Date
    }

    private let session: URLSession
    private let cacheDirectory: URL

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = base.appendingPathComponent("SeaSignalForecasts", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func data(for url: URL, maxAge: TimeInterval, allowStaleOnError: Bool = true) async throws -> CachedHTTPResponse {
        let fileURL = cacheFile(for: url)
        let cached = load(from: fileURL)
        if let cached, Date().timeIntervalSince(cached.fetchedAt) <= maxAge {
            return CachedHTTPResponse(data: cached.data, fetchedAt: cached.fetchedAt, isStale: false)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("SeaSignal/1.0 (iOS marine forecast app)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let entry = Entry(data: data, fetchedAt: Date())
            save(entry, to: fileURL)
            return CachedHTTPResponse(data: data, fetchedAt: entry.fetchedAt, isStale: false)
        } catch {
            if allowStaleOnError, let cached {
                return CachedHTTPResponse(data: cached.data, fetchedAt: cached.fetchedAt, isStale: true)
            }
            throw error
        }
    }

    private func cacheFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name).appendingPathExtension("jsoncache")
    }

    private func load(from url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func save(_ entry: Entry, to url: URL) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

