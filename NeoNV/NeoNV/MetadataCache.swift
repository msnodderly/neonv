import Foundation
import os

/// Cached representation of a note's metadata for fast startup.
struct CachedNote: Codable {
    let relativePath: String
    let modificationDate: Date
    let title: String
    let contentPreview: String
}

/// On-disk index of note metadata for instant warm starts.
///
/// On launch, the cache is loaded and displayed immediately while a background
/// validation pass compares modification dates against the filesystem and
/// refreshes any stale entries.
struct MetadataCache {
    /// Current cache format version. Bump when the Codable layout changes.
    private static let formatVersion = 1

    private struct CacheEnvelope: Codable {
        let version: Int
        let folderPath: String
        let notes: [CachedNote]
    }

    // MARK: - Cache location

    /// Returns the cache file URL for a given notes folder.
    static func cacheURL(for folderURL: URL) -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("net.area51a.NeoNV", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Use a hash of the folder path so different folders get separate caches.
        let hash = folderURL.path.utf8.reduce(into: UInt64(5381)) { h, byte in
            h = h &* 33 &+ UInt64(byte)
        }
        return cacheDir.appendingPathComponent("notes-index-\(hash).json")
    }

    // MARK: - Read / Write

    /// Loads cached notes for `folderURL`. Returns `nil` if the cache is
    /// missing, corrupt, or was written by a different format version.
    static func load(for folderURL: URL) -> [CachedNote]? {
        let url = cacheURL(for: folderURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data) else { return nil }
        guard envelope.version == formatVersion else { return nil }
        guard envelope.folderPath == folderURL.path else { return nil }
        return envelope.notes
    }

    /// Persists the current note list to disk. Runs on a background queue
    /// so it never blocks the main thread.
    static func save(_ notes: [NoteFile], for folderURL: URL) {
        let cached = notes.compactMap { note -> CachedNote? in
            guard !note.isUnsaved else { return nil }
            return CachedNote(
                relativePath: note.relativePath,
                modificationDate: note.modificationDate,
                title: note.title,
                contentPreview: note.contentPreview
            )
        }
        let envelope = CacheEnvelope(version: formatVersion, folderPath: folderURL.path, notes: cached)
        let url = cacheURL(for: folderURL)
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Removes the cache file for a folder (e.g. when the user switches folders).
    static func invalidate(for folderURL: URL) {
        let url = cacheURL(for: folderURL)
        try? FileManager.default.removeItem(at: url)
    }
}
