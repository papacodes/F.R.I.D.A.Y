import Foundation
import NaturalLanguage
import SQLite3

// MARK: - RAGSkill
//
// Semantic search over ~/Documents/notes/**/*.md.
// Uses NLEmbedding (sentence-level, built-in macOS) for embeddings and SQLite for persistence.
//
// Indexing is incremental — only files whose modification timestamp changed are re-chunked.
// The in-memory cache (chunkCache + vectorCache) is populated after each index run so retrieval
// never touches the DB on the hot path.
//
// Called by Gemini via the retrieve_knowledge tool instead of ad-hoc read_file queries.

actor RAGSkill {

    static let shared = RAGSkill()

    private let notesRoot: String
    private let dbPath: String
    private var db: OpaquePointer?
    private var nlEmbedding: NLEmbedding?

    // Hot-path cache — rebuilt after each index run
    private var chunkCache: [Chunk] = []
    private var vectorCache: [Int64: [Float]] = [:]

    private var isIndexed  = false
    private var isIndexing = false

    init() {
        notesRoot = ("~/Documents/notes" as NSString).expandingTildeInPath
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Friday", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("knowledge.db").path
    }

    // MARK: - Public

    /// Kick off background indexing at app launch. Returns immediately.
    static func startIndexing() {
        Task.detached(priority: .background) {
            await shared.ensureIndexed()
        }
    }

    /// Semantic search. Blocks until index is ready on first call, then answers from cache.
    static func retrieve(query: String) async -> String {
        await shared.retrieveInternal(query: query)
    }

    // MARK: - Core

    private func ensureIndexed() async {
        guard !isIndexed, !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        openDB()
        createSchema()
        nlEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

        guard nlEmbedding != nil else {
            print("Friday: RAG — NLEmbedding unavailable, knowledge search disabled")
            return
        }

        await indexChangedFiles()
        loadCache()
        isIndexed = true
        print("Friday: RAG ready — \(chunkCache.count) chunks, \(vectorCache.count) vectors")
    }

    private func retrieveInternal(query: String) async -> String {
        if !isIndexed {
            if isIndexing {
                // Background indexing is already running — wait for it rather than returning an
                // empty-cache error. Polls every 200ms; indexing 1000+ chunks takes ~5-10s.
                while isIndexing {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            } else {
                await ensureIndexed()
            }
        }

        guard let emb = nlEmbedding else {
            return "Knowledge search unavailable — embedding model not loaded."
        }
        guard !chunkCache.isEmpty else {
            return "Knowledge index is empty — notes may still be indexing."
        }
        guard let queryVec = emb.vector(for: query)?.map({ Float($0) }) else {
            return "Could not embed query."
        }

        let top = chunkCache
            .compactMap { chunk -> (Float, Chunk)? in
                guard let vec = vectorCache[chunk.id] else { return nil }
                return (cosineSimilarity(queryVec, vec), chunk)
            }
            .sorted { $0.0 > $1.0 }
            .prefix(3)

        guard !top.isEmpty else { return "No relevant knowledge found for: \(query)" }

        return top.map { _, chunk in
            // Show path relative to notes root for readability
            let rel = chunk.filePath.hasPrefix(notesRoot + "/")
                ? String(chunk.filePath.dropFirst(notesRoot.count + 1))
                : (chunk.filePath as NSString).lastPathComponent
            let section = chunk.heading.isEmpty ? "" : " §\(chunk.heading)"
            return "[\(rel)\(section)]\n\(chunk.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Indexing

    private func indexChangedFiles() async {
        // Collect URLs on a non-isolated function — FileManager.enumerator's iterator
        // is unavailable from async contexts in Swift 6 strict concurrency.
        let urls = collectMarkdownURLs(root: notesRoot)

        var indexed = 0
        for (url, modTime) in urls {
            if isFileUpToDate(path: url.path, modTime: modTime) { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let chunks = chunk(content, filePath: url.path)
            deleteChunks(forPath: url.path)

            for c in chunks {
                guard let vec = nlEmbedding?.vector(for: c.content)?.map({ Float($0) }) else { continue }
                let id = insertChunk(c, modTime: modTime)
                guard id > 0 else { continue }
                insertVector(chunkId: id, vector: vec)
                indexed += 1
            }
        }

        if indexed > 0 { print("Friday: RAG indexed \(indexed) chunks") }
    }

    private func loadCache() {
        var chunks: [Chunk] = []
        if let stmt = prepare("SELECT id, file_path, heading, content FROM chunks") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                chunks.append(Chunk(
                    id:       sqlite3_column_int64(stmt, 0),
                    filePath: str(sqlite3_column_text(stmt, 1)),
                    heading:  str(sqlite3_column_text(stmt, 2)),
                    content:  str(sqlite3_column_text(stmt, 3))
                ))
            }
            sqlite3_finalize(stmt)
        }

        var vectors: [Int64: [Float]] = [:]
        if let stmt = prepare("SELECT chunk_id, vector FROM embeddings") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let byteCount = Int(sqlite3_column_bytes(stmt, 1))
                let floatCount = byteCount / MemoryLayout<Float>.size
                if let blob = sqlite3_column_blob(stmt, 1), floatCount > 0 {
                    vectors[id] = Array(UnsafeBufferPointer(
                        start: blob.assumingMemoryBound(to: Float.self),
                        count: floatCount
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }

        chunkCache = chunks
        vectorCache = vectors
    }

    // MARK: - Chunking

    private func chunk(_ content: String, filePath: String) -> [Chunk] {
        var chunks: [Chunk] = []
        var currentHeading = ""
        var buffer = ""

        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            guard text.count > 40 else { return }  // skip trivially short sections

            // Sub-chunk sections that exceed 800 chars so embeddings stay meaningful
            var idx = text.startIndex
            while idx < text.endIndex {
                let end = text.index(idx, offsetBy: 800, limitedBy: text.endIndex) ?? text.endIndex
                let slice = String(text[idx..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !slice.isEmpty {
                    chunks.append(Chunk(id: 0, filePath: filePath, heading: currentHeading, content: slice))
                }
                idx = end
            }
        }

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                flush()
                currentHeading = String(line.drop(while: { $0 == "#" || $0 == " " }))
            } else {
                buffer += line + "\n"
            }
        }
        flush()
        return chunks
    }

    // MARK: - Math

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0; var na: Float = 0; var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na  += a[i] * a[i]
            nb  += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - SQLite

    private func openDB() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("Friday: RAG — failed to open DB at \(dbPath)")
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;", nil, nil, nil)
    }

    private func createSchema() {
        sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS chunks (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path     TEXT NOT NULL,
            heading       TEXT NOT NULL DEFAULT '',
            content       TEXT NOT NULL,
            file_modified REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS embeddings (
            chunk_id INTEGER PRIMARY KEY,
            vector   BLOB    NOT NULL,
            FOREIGN KEY(chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(file_path);
        """, nil, nil, nil)
    }

    private func isFileUpToDate(path: String, modTime: Double) -> Bool {
        guard let stmt = prepare("SELECT file_modified FROM chunks WHERE file_path = ? LIMIT 1")
        else { return false }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return abs(sqlite3_column_double(stmt, 0) - modTime) < 1.0
    }

    private func deleteChunks(forPath path: String) {
        guard let stmt = prepare("DELETE FROM chunks WHERE file_path = ?") else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, path)
        sqlite3_step(stmt)
    }

    private func insertChunk(_ c: Chunk, modTime: Double) -> Int64 {
        guard let stmt = prepare(
            "INSERT INTO chunks (file_path, heading, content, file_modified) VALUES (?, ?, ?, ?)"
        ) else { return -1 }
        defer { sqlite3_finalize(stmt) }
        // Keep NSStrings alive across bind + step so SQLITE_STATIC is safe
        let ns = [c.filePath as NSString, c.heading as NSString, c.content as NSString]
        sqlite3_bind_text(stmt, 1, ns[0].utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, ns[1].utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ns[2].utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, modTime)
        return sqlite3_step(stmt) == SQLITE_DONE ? sqlite3_last_insert_rowid(db) : -1
    }

    private func insertVector(chunkId: Int64, vector: [Float]) {
        guard let stmt = prepare(
            "INSERT OR REPLACE INTO embeddings (chunk_id, vector) VALUES (?, ?)"
        ) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, chunkId)
        _ = vector.withUnsafeBytes { buf in
            sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count), nil)
        }
        sqlite3_step(stmt)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    /// Bind a String param. The NSString is kept alive by the caller's local binding.
    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        let ns = value as NSString
        _ = withExtendedLifetime(ns) {
            sqlite3_bind_text(stmt, index, ns.utf8String, -1, nil)
        }
    }

    /// Safe bridge from sqlite3_column_text (nullable C string) to Swift String.
    private func str(_ ptr: UnsafePointer<UInt8>?) -> String {
        ptr.map { String(cString: $0) } ?? ""
    }
}

// MARK: - Sync File Collection

/// Collects all .md URLs under `root`, skipping hidden files and the /memory/ folder.
/// This is a plain sync function — safe to call from nonisolated or actor contexts
/// because FileManager.enumerator's Sequence iterator is unavailable in async contexts (Swift 6).
private func collectMarkdownURLs(root: String) -> [(url: URL, modTime: Double)] {
    guard let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: root),
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var result: [(URL, Double)] = []
    for case let url as URL in enumerator {
        guard url.pathExtension == "md",
              !url.path.contains("/memory/") else { continue }
        let modTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap { $0.contentModificationDate }?.timeIntervalSince1970 ?? 0
        result.append((url, modTime))
    }
    return result
}

// MARK: - Chunk

private struct Chunk {
    let id: Int64
    let filePath: String
    let heading: String
    let content: String
}
