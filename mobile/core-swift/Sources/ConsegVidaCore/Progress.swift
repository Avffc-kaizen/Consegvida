import Foundation

public struct Completion: Codable, Hashable, Identifiable, Sendable {
    public let missionId: String
    public let completedOn: LocalDay
    public var id: String { "\(missionId)|\(completedOn.rawValue)" }

    public init(missionId: String, completedOn: LocalDay) {
        self.missionId = missionId
        self.completedOn = completedOn
    }

    private enum CodingKeys: String, CodingKey { case missionId, completedOn }

    public init(from decoder: Decoder) throws {
        try requireKeys(["missionId", "completedOn"], in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        missionId = try container.decode(String.self, forKey: .missionId)
        completedOn = try container.decode(LocalDay.self, forKey: .completedOn)
    }
}

private struct AnyStateKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireKeys(_ expected: Set<String>, in decoder: Decoder) throws {
    let allKeys = try decoder.container(keyedBy: AnyStateKey.self).allKeys.map(\.stringValue)
    guard Set(allKeys) == expected else { throw ConsegVidaError.invalidState }
}

public struct ProgressState: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var activeMission: String?
    public private(set) var completions: [Completion]

    public static var empty: Self { Self(version: 1, activeMission: nil, completions: []) }

    private init(version: Int, activeMission: String?, completions: [Completion]) {
        self.version = version
        self.activeMission = activeMission
        self.completions = completions
    }

    private enum CodingKeys: String, CodingKey { case version, activeMission, completions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else { throw ConsegVidaError.unsupportedVersion(version) }
        try requireKeys(["version", "activeMission", "completions"], in: decoder)
        guard container.contains(.activeMission) else { throw ConsegVidaError.invalidState }
        activeMission = try container.decodeIfPresent(String.self, forKey: .activeMission)
        completions = try container.decode([Completion].self, forKey: .completions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        if let activeMission { try container.encode(activeMission, forKey: .activeMission) }
        else { try container.encodeNil(forKey: .activeMission) }
        try container.encode(completions, forKey: .completions)
    }

    public func completed(_ missionID: String, on day: LocalDay) -> Bool {
        completions.contains { $0.missionId == missionID && $0.completedOn == day }
    }

    public func validate(knownMissionIDs: Set<String>, today: LocalDay) throws {
        guard version == 1 else { throw ConsegVidaError.unsupportedVersion(version) }
        guard completions.count <= ProgressCodec.maximumCompletions else { throw ConsegVidaError.completionLimit }
        if let activeMission, !knownMissionIDs.contains(activeMission) {
            throw ConsegVidaError.unknownMission(activeMission)
        }
        var keys = Set<String>()
        for completion in completions {
            guard knownMissionIDs.contains(completion.missionId) else {
                throw ConsegVidaError.unknownMission(completion.missionId)
            }
            // A recorded local day remains valid if the clock or time zone moves backwards.
            // Only a new completion is checked against the current local day.
            guard keys.insert(completion.id).inserted else { throw ConsegVidaError.invalidState }
        }
    }

    public mutating func start(_ missionID: String, today: LocalDay, knownMissionIDs: Set<String>) throws {
        try validate(knownMissionIDs: knownMissionIDs, today: today)
        guard knownMissionIDs.contains(missionID) else { throw ConsegVidaError.unknownMission(missionID) }
        guard !completed(missionID, on: today) else { throw ConsegVidaError.alreadyCompleted }
        activeMission = missionID
    }

    /// Returns false without changing any state for an already recorded mission/day.
    @discardableResult
    public mutating func complete(
        _ missionID: String, on day: LocalDay, today: LocalDay, knownMissionIDs: Set<String>
    ) throws -> Bool {
        try validate(knownMissionIDs: knownMissionIDs, today: today)
        guard knownMissionIDs.contains(missionID) else { throw ConsegVidaError.unknownMission(missionID) }
        guard day <= today else { throw ConsegVidaError.futureCompletion }
        if completed(missionID, on: day) { return false }
        guard activeMission == missionID else { throw ConsegVidaError.missionNotActive }
        guard completions.count < ProgressCodec.maximumCompletions else { throw ConsegVidaError.completionLimit }
        completions.append(Completion(missionId: missionID, completedOn: day))
        activeMission = nil
        return true
    }

    public mutating func reset() { self = .empty }
}

public enum ProgressCodec {
    public static let maximumBytes = 1_048_576
    public static let maximumCompletions = 10_000

    public static func decode(_ data: Data, knownMissionIDs: Set<String>, today: LocalDay) throws -> ProgressState {
        guard data.count <= maximumBytes else { throw ConsegVidaError.fileTooLarge }
        try JSONIntegrity.validate(data, onlyIntegerNumbers: true)
        let state: ProgressState
        do { state = try JSONDecoder().decode(ProgressState.self, from: data) }
        catch let error as ConsegVidaError { throw error }
        catch { throw ConsegVidaError.invalidState }
        try state.validate(knownMissionIDs: knownMissionIDs, today: today)
        return state
    }

    public static func encode(_ state: ProgressState, knownMissionIDs: Set<String>, today: LocalDay) throws -> Data {
        try state.validate(knownMissionIDs: knownMissionIDs, today: today)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= maximumBytes else { throw ConsegVidaError.fileTooLarge }
        return data
    }
}
