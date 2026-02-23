import Foundation

struct PersistenceManager {
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Project State

    static func save(_ state: ProjectState, to url: URL) throws {
        let data = try encoder.encode(state)
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("project.tmp.json")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
    }

    static func load(from url: URL) throws -> ProjectState {
        let data = try Data(contentsOf: url)
        return try decoder.decode(ProjectState.self, from: data)
    }

    // MARK: - Events

    static func appendEvent(_ event: Event, logURL: URL) throws {
        let data = try encoder.encode(event)
        guard let line = String(data: data, encoding: .utf8) else { return }
        let oneLine = line.components(separatedBy: .newlines).joined() + "\n"
        if FileManager.default.fileExists(atPath: logURL.path) {
            let fileHandle = try FileHandle(forWritingTo: logURL)
            fileHandle.seekToEndOfFile()
            if let appendData = oneLine.data(using: .utf8) {
                fileHandle.write(appendData)
            }
            fileHandle.closeFile()
        } else {
            try oneLine.data(using: .utf8)?.write(to: logURL)
        }
    }

    static func loadEvents(logURL: URL) throws -> [Event] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let content = try String(contentsOf: logURL, encoding: .utf8)
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Event.self, from: data)
            }
    }

    // MARK: - Snapshots

    static func saveSnapshot(_ state: ProjectState, description: String, dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "T")
        let safeName = description
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(timestamp)_\(safeName).json"
        let url = dir.appendingPathComponent(filename)
        let data = try encoder.encode(state)
        try data.write(to: url)
    }

    static func listSnapshots(dir: URL) -> [(name: String, url: URL)] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return dateA > dateB
            }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return (name: name, url: url)
            }
    }

    static func loadSnapshot(from url: URL) throws -> ProjectState {
        let data = try Data(contentsOf: url)
        return try decoder.decode(ProjectState.self, from: data)
    }

    // MARK: - Project Directory

    static func projectURL(named name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Flowtrace/\(name)")
    }

    static func allProjects() -> [(name: String, url: URL)] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("Flowtrace")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .filter { url in
                FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path)
            }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return dateA > dateB
            }
            .map { url in (name: url.lastPathComponent, url: url) }
    }
}
