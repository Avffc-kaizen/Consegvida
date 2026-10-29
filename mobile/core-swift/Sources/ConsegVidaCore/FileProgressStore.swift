import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Stores only the v1 progress contract. No credentials, analytics or user-entered text.
public struct FileProgressStore: Sendable {
    public let directory: URL
    public let knownMissionIDs: Set<String>
    public var fileURL: URL { directory.appendingPathComponent("progress-v1.json", isDirectory: false) }

    public init(directory: URL, knownMissionIDs: Set<String>) {
        self.directory = directory
        self.knownMissionIDs = knownMissionIDs
    }

    public func load(today: LocalDay) throws -> ProgressState {
        let data: Data
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ConsegVidaError.readFailed }
            guard let bytes = values.fileSize, bytes <= ProgressCodec.maximumBytes else { throw ConsegVidaError.fileTooLarge }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            data = try handle.read(upToCount: ProgressCodec.maximumBytes + 1) ?? Data()
        } catch let error as ConsegVidaError { throw error }
        catch {
            if isMissingFile(error) { return .empty }
            throw ConsegVidaError.readFailed
        }
        // Never change the file on a decode or validation error.
        return try ProgressCodec.decode(data, knownMissionIDs: knownMissionIDs, today: today)
    }

    public func save(_ state: ProgressState, today: LocalDay) throws {
        let data = try ProgressCodec.encode(state, knownMissionIDs: knownMissionIDs, today: today)
        let temporaryURL = directory.appendingPathComponent(".progress-\(UUID().uuidString).tmp")
        do {
            try prepareDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            #if os(iOS)
            try data.write(to: temporaryURL, options: [.withoutOverwriting, .completeFileProtection])
            #else
            try data.write(to: temporaryURL, options: [.withoutOverwriting])
            #endif
            try excludeFromBackup(temporaryURL)
            // Same-directory POSIX rename atomically replaces the old file, preserving the
            // protection/backup metadata already set on the new file. No fallible work follows.
            guard rename(temporaryURL.path, fileURL.path) == 0 else { throw ConsegVidaError.writeFailed }
        } catch { throw ConsegVidaError.writeFailed }
    }

    /// Call only after an explicit confirmation. This also recovers invalid state.
    public func erase() throws {
        do {
            // A terminated write can leave an owned temporary file. Explicit erasure must
            // remove those bytes too, without traversing directories or unrelated files.
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            for entry in entries {
                let name = entry.lastPathComponent
                guard name.hasPrefix(".progress-"), name.hasSuffix(".tmp"),
                      UUID(uuidString: String(name.dropFirst(10).dropLast(4))) != nil else { continue }
                let type = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if type.isRegularFile == true || type.isSymbolicLink == true {
                    try FileManager.default.removeItem(at: entry)
                }
            }
            try FileManager.default.removeItem(at: fileURL)
        }
        catch {
            if isMissingFile(error) { return }
            throw ConsegVidaError.writeFailed
        }
    }

    private func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain &&
            [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }

    private func excludeFromBackup(_ originalURL: URL) throws {
        #if os(iOS) || os(macOS)
        var url = originalURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #endif
    }
}
