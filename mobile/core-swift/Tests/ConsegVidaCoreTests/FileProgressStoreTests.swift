import Foundation
import XCTest
@testable import ConsegVidaCore

final class FileProgressStoreTests: XCTestCase {
    private let ids: Set<String> = ["fisico-entorno", "mental-foco", "espiritual-presenca"]
    private let today = try! LocalDay(validating: "2026-10-29")

    func testMissingFileReturnsEmptyWithoutCreatingOne() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.load(today: today), .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testRealAtomicWriteSurvivesFreshStoreInstance() throws {
        let store = try makeStore()
        var state = ProgressState.empty
        try state.start("mental-foco", today: today, knownMissionIDs: ids)
        try store.save(state, today: today)
        let fresh = FileProgressStore(directory: store.directory, knownMissionIDs: ids)
        XCTAssertEqual(try fresh.load(today: today), state)
        try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids)
        try fresh.save(state, today: today)
        XCTAssertEqual(try store.load(today: today), state)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), ["progress-v1.json"])
    }

    func testCorruptFilePreservedUntilExplicitErase() throws {
        let store = try makeStore()
        let corrupt = Data("broken state".utf8)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(today: today))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
        try store.erase()
        XCTAssertEqual(try store.load(today: today), .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testFutureVersionPreserved() throws {
        let store = try makeStore()
        let unknown = Data(#"{"version":9,"activeMission":null,"completions":[]}"#.utf8)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try unknown.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(today: today)) {
            XCTAssertEqual($0 as? ConsegVidaError, .unsupportedVersion(9))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), unknown)
    }

    func testRealWriteFailureIsReportedAndDoesNotClaimSuccess() throws {
        let directory = try temporaryDirectory()
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("existing file".utf8).write(to: blocker)
        let store = FileProgressStore(directory: blocker, knownMissionIDs: ids)
        XCTAssertThrowsError(try store.save(.empty, today: today)) {
            XCTAssertEqual($0 as? ConsegVidaError, .writeFailed)
        }
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "existing file")
    }

    func testOversizedStoredFileIsPreserved() throws {
        let store = try makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(repeating: 32, count: 1_048_577).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(today: today)) {
            XCTAssertEqual($0 as? ConsegVidaError, .fileTooLarge)
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL).count, 1_048_577)
    }

    func testDirectoryAndSymlinkCannotBeLoadedAsState() throws {
        let store = try makeStore()
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.load(today: today))
        try FileManager.default.removeItem(at: store.fileURL)
        let target = store.directory.appendingPathComponent("other.json")
        try Data(#"{"version":1,"activeMission":null,"completions":[]}"#.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: target)
        XCTAssertThrowsError(try store.load(today: today))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testEraseIsIdempotentAndClearsBothKindsOfProgress() throws {
        let store = try makeStore()
        var state = ProgressState.empty
        try state.start("mental-foco", today: today, knownMissionIDs: ids)
        try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids)
        try state.start("fisico-entorno", today: today, knownMissionIDs: ids)
        try store.save(state, today: today)
        try store.erase()
        try store.erase()
        XCTAssertEqual(try store.load(today: today), .empty)
    }

    func testExplicitEraseAlsoRemovesOwnedOrphanedTemporaryFiles() throws {
        let store = try makeStore()
        try store.save(.empty, today: today)
        let orphan = store.directory.appendingPathComponent(".progress-\(UUID().uuidString).tmp")
        let unrelated = store.directory.appendingPathComponent("keep.txt")
        try Data("old progress bytes".utf8).write(to: orphan)
        try Data("unrelated".utf8).write(to: unrelated)
        try store.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "unrelated")
    }

    #if os(macOS)
    func testBackupExclusionSurvivesAtomicReplacement() throws {
        let store = try makeStore()
        try store.save(.empty, today: today)
        try store.save(.empty, today: today)
        XCTAssertEqual(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    #endif

    private func makeStore() throws -> FileProgressStore {
        FileProgressStore(directory: try temporaryDirectory().appendingPathComponent("progress", isDirectory: true), knownMissionIDs: ids)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("consegvida-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
