import Foundation
import Testing
@testable import ReclockKit

@Suite("Persistence", .serialized)
struct PersistenceTests {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("reclock-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private func sampleState() throws -> AppState {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        var state = AppState(
            profile: profile,
            trips: [trip],
            plans: [plan],
            onboardingComplete: true
        )
        state.setTravelerState(TravelerState(asOf: TestSupport.reference), forTrip: trip.id)
        return state
    }

    @Test("Save and load round-trip")
    func saveLoad() async throws {
        let url = tempStoreURL()
        let store = JSONStore(fileURL: url)
        let state = try sampleState()
        try await store.save(state)

        // A brand-new store instance must read the same state back from disk.
        let reloaded = try await JSONStore(fileURL: url).load()
        #expect(reloaded == state)
    }

    @Test("Fresh store starts empty")
    func freshStart() async throws {
        let store = JSONStore(fileURL: tempStoreURL())
        let state = try await store.load()
        #expect(state.trips.isEmpty)
        #expect(state.profile == nil)
        #expect(!state.onboardingComplete)
    }

    @Test("Corrupted file is quarantined, not fatal")
    func corruptionRecovery() async throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("{not json at all??".utf8).write(to: url)

        let store = JSONStore(fileURL: url)
        let state = try await store.load()
        #expect(state.trips.isEmpty, "corrupt store must yield a fresh state")

        let quarantine = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        #expect(FileManager.default.fileExists(atPath: quarantine.path), "bad file should be kept for recovery")
        #expect(!FileManager.default.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) == nil)
    }

    @Test("v0 → v1 migration")
    func migration() async throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // v0 format: payload fields at top level alongside schemaVersion.
        let v0 = """
        {
          "schemaVersion": 0,
          "trips": [],
          "plans": [],
          "travelerStates": {},
          "surveys": [],
          "onboardingComplete": true,
          "settings": {"localOnlyMode": true, "analyticsEnabled": false, "timeDisplay": "dual"}
        }
        """
        try Data(v0.utf8).write(to: url)
        let state = try await JSONStore(fileURL: url).load()
        #expect(state.onboardingComplete)
        #expect(state.settings.localOnlyMode)
        #expect(state.settings.timeDisplay == .dual)
    }

    @Test("Wipe removes everything, including quarantined files")
    func wipe() async throws {
        let url = tempStoreURL()
        let store = JSONStore(fileURL: url)
        try await store.save(try sampleState())
        try await store.wipe()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let state = try await store.load()
        #expect(state.trips.isEmpty)
    }

    @Test("Export produces valid, complete JSON")
    func export() async throws {
        let url = tempStoreURL()
        let store = JSONStore(fileURL: url)
        let state = try sampleState()
        try await store.save(state)
        let data = try await store.exportData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["trips"] != nil)
        #expect(object?["profile"] != nil)
    }

    @Test("Share text is compact, essentials-only, and readable")
    func shareFormatter() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let text = PlanShareFormatter.text(trip: trip, plan: plan)

        #expect(text.contains("JFK → Helsinki"))
        #expect(text.contains("Sleep") || text.contains("sleep"))
        // Optional-priority actions (melatonin is always optional) never appear in shares.
        #expect(!text.contains("melatonin"))
        #expect(!text.contains("Optional:"))
        // Fits on a screen-ish: essentials only.
        #expect(text.split(separator: "\n").count < 80)
    }

    @Test("Settings round-trip preserves the selected trip")
    func selectedTripPersists() async throws {
        let url = tempStoreURL()
        let store = JSONStore(fileURL: url)
        var state = try sampleState()
        state.settings.selectedTripID = state.trips[0].id
        try await store.save(state)
        let reloaded = try await JSONStore(fileURL: url).load()
        #expect(reloaded.settings.selectedTripID == state.trips[0].id)
    }

    @Test("Model coding is stable across encode/decode")
    func modelCoding() throws {
        let state = try sampleState()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(AppState.self, from: data)
        // ISO8601 truncates sub-second precision; our dates are all 5-minute-rounded, so
        // full equality must hold.
        #expect(decoded == state)
    }
}
