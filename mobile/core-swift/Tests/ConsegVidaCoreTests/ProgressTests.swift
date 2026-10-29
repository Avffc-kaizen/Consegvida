import Foundation
import XCTest
@testable import ConsegVidaCore

final class ProgressTests: XCTestCase {
    private let today = try! LocalDay(validating: "2026-10-29")
    private let ids: Set<String> = ["fisico-entorno", "mental-foco", "espiritual-presenca"]

    func testCanonicalContentLoadsWithThreeDifferentAxes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "content", withExtension: "json"))
        let content = try Content.decode(Data(contentsOf: url))
        XCTAssertEqual(content.appName, "ConsegVida")
        XCTAssertEqual(content.phase, "Fase 1 — Despertar")
        XCTAssertEqual(content.missionIDs, ids)
        XCTAssertEqual(Set(content.axes.map(\.id)), Set(["fisico", "mental", "espiritual"]))
        XCTAssertEqual(content.colors["navy"], "#12203A")
        XCTAssertEqual(content.colors["cream"], "#F3EFE6")
        XCTAssertEqual(content.colors["gold"], "#B89A5B")
    }

    func testStartingAndCompletingClearsActiveAndAddsOneRecord() throws {
        var state = ProgressState.empty
        try state.start("mental-foco", today: today, knownMissionIDs: ids)
        XCTAssertEqual(state.activeMission, "mental-foco")
        XCTAssertTrue(try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids))
        XCTAssertNil(state.activeMission)
        XCTAssertEqual(state.completions, [Completion(missionId: "mental-foco", completedOn: today)])
    }

    func testDuplicateCompletionIsIdempotentEvenWithAnotherActiveMission() throws {
        var state = try completedState()
        try state.start("fisico-entorno", today: today, knownMissionIDs: ids)
        let before = state
        XCTAssertFalse(try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids))
        XCTAssertEqual(state, before)
    }

    func testNewCompletionRequiresSameActiveMission() throws {
        var state = ProgressState.empty
        XCTAssertThrowsError(try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids)) {
            XCTAssertEqual($0 as? ConsegVidaError, .missionNotActive)
        }
        XCTAssertEqual(state, .empty)
        try state.start("fisico-entorno", today: today, knownMissionIDs: ids)
        XCTAssertThrowsError(try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids))
        XCTAssertEqual(state.activeMission, "fisico-entorno")
    }

    func testNextLocalDayCanCompleteSameMissionAgain() throws {
        let tomorrow = try LocalDay(validating: "2026-10-30")
        var state = try completedState()
        try state.start("mental-foco", today: tomorrow, knownMissionIDs: ids)
        try state.complete("mental-foco", on: tomorrow, today: tomorrow, knownMissionIDs: ids)
        XCTAssertEqual(state.completions.map(\.completedOn), [today, tomorrow])
    }

    func testStartingAlreadyCompletedTodayFailsWithoutMutation() throws {
        var state = try completedState()
        let before = state
        XCTAssertThrowsError(try state.start("mental-foco", today: today, knownMissionIDs: ids)) {
            XCTAssertEqual($0 as? ConsegVidaError, .alreadyCompleted)
        }
        XCTAssertEqual(state, before)
    }

    func testFutureCompletionRejectedWithoutMutation() throws {
        var state = ProgressState.empty
        try state.start("mental-foco", today: today, knownMissionIDs: ids)
        let before = state
        XCTAssertThrowsError(try state.complete("mental-foco", on: LocalDay(validating: "2026-10-30"), today: today, knownMissionIDs: ids)) {
            XCTAssertEqual($0 as? ConsegVidaError, .futureCompletion)
        }
        XCTAssertEqual(state, before)
    }

    func testUnknownMissionRejected() throws {
        var state = ProgressState.empty
        XCTAssertThrowsError(try state.start("seguro-auto", today: today, knownMissionIDs: ids))
        XCTAssertThrowsError(try state.complete("seguro-auto", on: today, today: today, knownMissionIDs: ids))
        XCTAssertEqual(state, .empty)
    }

    func testResetRemovesActiveAndCompletedState() throws {
        var state = try completedState()
        try state.start("fisico-entorno", today: today, knownMissionIDs: ids)
        state.reset()
        XCTAssertEqual(state, .empty)
    }

    func testStrictGregorianDatesAndLeapYears() {
        for date in ["0001-01-01", "9999-12-31", "2000-02-29", "2024-02-29"] {
            XCTAssertNotNil(LocalDay(rawValue: date), date)
        }
        for date in ["0000-01-01", "1900-02-29", "2025-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "2026-01-00", "2026-1-01", "2026-01-1", "2026-01-01T00:00:00Z", "٢٠٢٦-01-01"] {
            XCTAssertNil(LocalDay(rawValue: date), date)
        }
    }

    func testLocalDayRespectsTimeZoneAtMidnight() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-29T01:30:00Z"))
        XCTAssertEqual(try LocalDay.containing(instant, timeZone: XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))).rawValue, "2026-10-28")
        XCTAssertEqual(try LocalDay.containing(instant, timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))).rawValue, "2026-10-29")
    }

    func testStateRoundTripWritesExplicitNull() throws {
        let data = try ProgressCodec.encode(ProgressState.empty, knownMissionIDs: ids, today: today)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["activeMission"] is NSNull)
        XCTAssertEqual(try ProgressCodec.decode(data, knownMissionIDs: ids, today: today), .empty)
        let state = try completedState()
        XCTAssertEqual(try ProgressCodec.decode(ProgressCodec.encode(state, knownMissionIDs: ids, today: today), knownMissionIDs: ids, today: today), state)
    }

    func testUnsupportedVersionIsRejectedExplicitly() {
        assertInvalid(#"{"version":2,"activeMission":null,"completions":[]}"#, expected: .unsupportedVersion(2))
    }

    func testMissingRequiredFieldsAndWrongTypesRejected() {
        for json in [#"{"version":1,"completions":[]}"#, #"{"version":1,"activeMission":null}"#, #"{"version":1,"activeMission":4,"completions":[]}"#, #"{"version":true,"activeMission":null,"completions":[]}"#] {
            assertInvalid(json)
        }
    }

    func testUnknownFieldsAndNonIntegerVersionRepresentationRejected() {
        for json in [
            #"{"version":1,"activeMission":null,"completions":[],"journal":"must not disappear"}"#,
            #"{"version":1,"activeMission":null,"completions":[{"missionId":"mental-foco","completedOn":"2026-10-29","note":"must not disappear"}]}"#,
            #"{"version":1.0,"activeMission":null,"completions":[]}"#,
            #"{"version":1e0,"activeMission":null,"completions":[]}"#
        ] { assertInvalid(json) }
    }

    func testDuplicateJSONKeysRejectedIncludingEscapedKeySpelling() {
        assertInvalid(#"{"version":1,"version":1,"activeMission":null,"completions":[]}"#, expected: .duplicateJSONKey("version"))
        assertInvalid(#"{"version":1,"\u0076ersion":1,"activeMission":null,"completions":[]}"#, expected: .duplicateJSONKey("version"))
        assertInvalid(#"{"version":1,"activeMission":null,"completions":[{"missionId":"mental-foco","missionId":"mental-foco","completedOn":"2026-10-29"}]}"#, expected: .duplicateJSONKey("missionId"))
    }

    func testDuplicateCompletionRecordsRejected() {
        assertInvalid(#"{"version":1,"activeMission":null,"completions":[{"missionId":"mental-foco","completedOn":"2026-10-29"},{"missionId":"mental-foco","completedOn":"2026-10-29"}]}"#, expected: .invalidState)
    }

    func testUnknownMissionAndBadDateRejectedOnLoad() {
        assertInvalid(#"{"version":1,"activeMission":"missing","completions":[]}"#)
        assertInvalid(#"{"version":1,"activeMission":null,"completions":[{"missionId":"missing","completedOn":"2026-10-29"}]}"#)
        assertInvalid(#"{"version":1,"activeMission":null,"completions":[{"missionId":"mental-foco","completedOn":"2026-02-30"}]}"#)
    }

    func testClockRollbackKeepsHistoryAndAllowsOtherMission() throws {
        let recorded = Data(#"{"version":1,"activeMission":null,"completions":[{"missionId":"mental-foco","completedOn":"2026-10-30"}]}"#.utf8)
        var state = try ProgressCodec.decode(recorded, knownMissionIDs: ids, today: today)
        XCTAssertEqual(state.completions.first?.completedOn.rawValue, "2026-10-30")
        try state.start("fisico-entorno", today: today, knownMissionIDs: ids)
        try state.complete("fisico-entorno", on: today, today: today, knownMissionIDs: ids)
        XCTAssertEqual(state.completions.count, 2)
        XCTAssertThrowsError(try state.complete("espiritual-presenca", on: LocalDay(validating: "2026-10-30"), today: today, knownMissionIDs: ids)) {
            XCTAssertEqual($0 as? ConsegVidaError, .futureCompletion)
        }
    }

    func testOversizedInputRejectedBeforeDecode() {
        XCTAssertThrowsError(try ProgressCodec.decode(Data(repeating: 32, count: 1_048_577), knownMissionIDs: ids, today: today)) {
            XCTAssertEqual($0 as? ConsegVidaError, .fileTooLarge)
        }
    }

    func testRecordCountCapped() throws {
        let completion = #"{"missionId":"mental-foco","completedOn":"2026-10-29"}"#
        let json = #"{"version":1,"activeMission":null,"completions":["# + Array(repeating: completion, count: 10_001).joined(separator: ",") + "]}"
        assertInvalid(json, expected: .completionLimit)
    }

    func testInvalidJSONGrammarAndExcessiveDepthRejected() {
        for json in ["", "null", "[]", "{", #"{"version":01,"activeMission":null,"completions":[]}"#, #"{"version":1,"activeMission":null,"completions":[],}"#, #"{"version":1,"activeMission":null,"completions":[]} trailing"#, String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)] {
            assertInvalid(json)
        }
    }

    private func completedState() throws -> ProgressState {
        var state = ProgressState.empty
        try state.start("mental-foco", today: today, knownMissionIDs: ids)
        try state.complete("mental-foco", on: today, today: today, knownMissionIDs: ids)
        return state
    }

    private func assertInvalid(_ json: String, expected: ConsegVidaError? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ProgressCodec.decode(Data(json.utf8), knownMissionIDs: ids, today: today), file: file, line: line) { error in
            if let expected { XCTAssertEqual(error as? ConsegVidaError, expected, file: file, line: line) }
        }
    }
}
