import Foundation

protocol SnapshotRepository: AnyObject {
    func loadCandidates() -> [Data]
    func save(_ data: Data) throws
    func removeAll() throws
}

struct SnapshotLoadResult: Equatable {
    var usedBackup: Bool
    var migratedLegacyStorage: Bool
}

final class UserDefaultsSnapshotRepository: SnapshotRepository {
    static let defaultKey = "FitTune.snapshot.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func loadCandidates() -> [Data] {
        defaults.data(forKey: key).map { [$0] } ?? []
    }

    func save(_ data: Data) throws {
        defaults.set(data, forKey: key)
    }

    func removeAll() throws {
        defaults.removeObject(forKey: key)
    }
}

final class FileSnapshotRepository: SnapshotRepository {
    private let fileManager: FileManager
    private let directory: URL
    private let primaryURL: URL
    private let backupURL: URL

    convenience init(fileManager: FileManager = .default) {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.init(
            directory: applicationSupport.appendingPathComponent("FitTune", isDirectory: true),
            fileManager: fileManager
        )
    }

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        primaryURL = directory.appendingPathComponent("snapshot.json")
        backupURL = directory.appendingPathComponent("snapshot.backup.json")
    }

    func loadCandidates() -> [Data] {
        [primaryURL, backupURL].compactMap { try? Data(contentsOf: $0) }
    }

    func save(_ data: Data) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if fileManager.fileExists(atPath: primaryURL.path) {
            let previous = try Data(contentsOf: primaryURL)
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: primaryURL, options: .atomic)
    }

    func removeAll() throws {
        for url in [primaryURL, backupURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
