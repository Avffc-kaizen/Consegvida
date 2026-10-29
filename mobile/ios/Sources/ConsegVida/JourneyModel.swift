import Foundation
import SwiftUI
import ConsegVidaCore

@MainActor
final class JourneyModel: ObservableObject {
    @Published private(set) var state = ProgressState.empty
    @Published private(set) var today: LocalDay?
    @Published private(set) var isReady = false
    @Published private(set) var recoveryMessage: String?
    @Published var actionError: String?
    @Published var confirmsErase = false

    private(set) var content: Content?
    private(set) var contentError: String?
    private var store: FileProgressStore?

    init() {
        do {
            guard let url = Bundle.module.url(forResource: "content", withExtension: "json") else {
                throw ConsegVidaError.invalidContent
            }
            let content = try Content.decode(Data(contentsOf: url))
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw ConsegVidaError.readFailed
            }
            self.content = content
            store = FileProgressStore(
                directory: support.appendingPathComponent("ConsegVida", isDirectory: true),
                knownMissionIDs: content.missionIDs
            )
        } catch {
            contentError = error.localizedDescription
        }
    }

    func refresh() {
        guard let store else { return }
        do {
            let day = try LocalDay.containing(Date(), timeZone: .current)
            let loaded = try store.load(today: day)
            today = day
            state = loaded
            recoveryMessage = nil
            isReady = true
        } catch {
            recoveryMessage = error.localizedDescription
            isReady = false
        }
    }

    func hasCompleted(_ missionID: String) -> Bool {
        guard isReady, let today else { return false }
        return state.completed(missionID, on: today)
    }

    func start(_ missionID: String) {
        change { state, day, ids in try state.start(missionID, today: day, knownMissionIDs: ids) }
    }

    func complete(_ missionID: String) {
        change { state, day, ids in
            try state.complete(missionID, on: day, today: day, knownMissionIDs: ids)
        }
    }

    func eraseConfirmed() {
        guard let store else { return }
        do {
            try store.erase()
            state = .empty
            actionError = nil
            refresh()
        } catch { actionError = error.localizedDescription }
    }

    private func change(_ operation: (inout ProgressState, LocalDay, Set<String>) throws -> Void) {
        guard isReady, let store, let content else { return }
        do {
            // Re-read the local day at every action; the app may remain open past midnight.
            let day = try LocalDay.containing(Date(), timeZone: .current)
            var candidate = state
            try operation(&candidate, day, content.missionIDs)
            if candidate != state { try store.save(candidate, today: day) }
            // A failed write never publishes optimistic progress.
            state = candidate
            today = day
        } catch { actionError = error.localizedDescription }
    }
}
