import Foundation
import SwiftUI
import ReclockKit

// The plan assistant runs on Apple's on-device Foundation Models (iOS 26,
// Apple Intelligence hardware). Everything stays on the phone — same privacy
// story as the rest of Reclock. On older toolchains/devices this file compiles
// to a hidden stub, so CI on older Xcode and phones without Apple Intelligence
// are both fine.

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum PlanAssistant {

    static var isSupported: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Compact, current plan context the model can ground every answer in.
    @MainActor
    static func context(trip: Trip, model: AppModel) -> String {
        guard let plan = model.plan(for: trip) else { return "No plan yet." }
        let now = model.deps.now()
        let zone = trip.destinationZone.resolved
        var lines: [String] = []
        lines.append("Trip: \(trip.origin) → \(trip.destination).")
        lines.append("Shift needed: \(Int(plan.requiredShiftHours.rounded()))h \(plan.shiftDirection.rawValue). Strategy: \(plan.strategySummary)")
        lines.append("Intensity: \(trip.intensity.displayName).")
        if let today = plan.days.first(where: { $0.dayStart <= now && now < $0.dayStart.addingTimeInterval(86_400) }) {
            lines.append("Today (\(today.label)):")
            for action in plan.actions(onDay: today.index).sorted(by: { $0.window.start < $1.window.start }) {
                let status: String
                switch action.completion {
                case .done: status = "done"
                case .pending: status = "pending"
                default: status = "skipped"
                }
                lines.append("- \(TimeFormat.range(action.window, zone: zone)) \(action.title) [\(status)]")
            }
        }
        let pendingNext = plan.actions
            .filter { $0.completion == .pending && $0.window.start > now }
            .sorted { $0.window.start < $1.window.start }
            .prefix(3)
        if !pendingNext.isEmpty {
            lines.append("Next up: " + pendingNext
                .map { "\($0.title) at \(TimeFormat.time($0.window.start, zone: zone))" }
                .joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    /// What each tool should be called in the transcript while it runs.
    static func toolLabel(_ name: String) -> (text: String, symbol: String) {
        switch name {
        case "setPlanIntensity": ("Adjusting plan intensity", "slider.horizontal.3")
        case "setPreTripStartDays": ("Moving the pre-trip start", "calendar.badge.clock")
        case "markPlanAction": ("Updating a step", "checkmark.circle")
        default: ("Working on the plan", "wrench.and.screwdriver")
        }
    }

    @MainActor
    static func makeSession(
        trip: Trip,
        model: AppModel,
        onTool: @escaping @Sendable (String) async -> Void = { _ in }
    ) -> LanguageModelSession {
        let instructions = """
        You are Reclock's plan assistant: a calm, seasoned traveler who knows \
        circadian science cold.

        Voice: text like a trusted friend — warm, plain, direct. One to three \
        short sentences, never more. No lists, no headers, no emoji, no filler \
        like "great question" — just the answer. Say times plainly ("bed by \
        22:30, Tokyo time").

        Ground everything in the plan context below; never invent times. This is \
        general wellness guidance, never medical advice — for medication or \
        health conditions, point to a clinician in one kind sentence.

        When the traveler wants a change (gentler plan, start earlier, can't do \
        a step), call a tool, then confirm what changed in one line using the \
        tool's result.

        Current plan:
        \(context(trip: trip, model: model))
        """
        return LanguageModelSession(
            tools: [
                SetIntensityTool(model: model, tripID: trip.id, onTool: onTool),
                SetPreTripStartTool(model: model, tripID: trip.id, onTool: onTool),
                MarkActionTool(model: model, tripID: trip.id, onTool: onTool),
            ],
            instructions: instructions
        )
    }

    /// One-line summary of the rebuilt plan so the model can confirm changes truthfully.
    @MainActor
    static func keyTimesSummary(tripID: UUID, model: AppModel) -> String {
        guard let trip = model.state.trips.first(where: { $0.id == tripID }),
              let plan = model.plan(for: trip) else { return "Plan unavailable." }
        let now = model.deps.now()
        let zone = trip.destinationZone.resolved
        let nextSleep = plan.actions.first {
            $0.type == .sleep && $0.completion == .pending && $0.window.end > now
        }
        var parts: [String] = ["Plan rebuilt (intensity \(trip.intensity.displayName))."]
        if let nextSleep {
            parts.append("Next sleep \(TimeFormat.range(nextSleep.window, zone: zone)).")
        }
        let nextAction = plan.actions
            .filter { $0.completion == .pending && $0.window.start > now }
            .min { $0.window.start < $1.window.start }
        if let nextAction {
            parts.append("Next step: \(nextAction.title) at \(TimeFormat.time(nextAction.window.start, zone: zone)).")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Tools (the "authentic adjustment" part)

@available(iOS 26.0, *)
struct SetIntensityTool: Tool {
    let model: AppModel
    let tripID: UUID
    let onTool: @Sendable (String) async -> Void

    let name = "setPlanIntensity"
    let description = """
    Change how aggressive the jet lag plan is. Use when the traveler wants the plan \
    gentler/easier, more balanced, or faster/maximum. Rebuilds the plan.
    """

    @Generable
    struct Arguments {
        @Guide(description: "One of: easy, balanced, maximum")
        var level: String
    }

    func call(arguments: Arguments) async throws -> String {
        await onTool("setPlanIntensity")
        let summary: String = await MainActor.run {
            guard var trip = model.state.trips.first(where: { $0.id == tripID }) else {
                return "Trip not found."
            }
            switch arguments.level.lowercased() {
            case "easy": trip.intensity = .easy
            case "maximum": trip.intensity = .maximum
            default: trip.intensity = .balanced
            }
            let updated = trip
            Task { await model.updateTrip(updated) }
            return "Intensity set to \(updated.intensity.displayName). The plan is rebuilding; key times may shift a little."
        }
        // Give the rebuild a beat, then report real times.
        try? await Task.sleep(nanoseconds: 600_000_000)
        let times = await MainActor.run { PlanAssistant.keyTimesSummary(tripID: tripID, model: model) }
        return summary + " " + times
    }
}

@available(iOS 26.0, *)
struct SetPreTripStartTool: Tool {
    let model: AppModel
    let tripID: UUID
    let onTool: @Sendable (String) async -> Void

    let name = "setPreTripStartDays"
    let description = """
    Change how many days before departure the plan starts shifting the traveler \
    (0 to 4). Use when they want to start adjusting earlier, later, or only on \
    travel day. Rebuilds the plan.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Days before departure to start: 0, 1, 2, 3, or 4")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await onTool("setPreTripStartDays")
        let summary: String = await MainActor.run {
            guard var trip = model.state.trips.first(where: { $0.id == tripID }) else {
                return "Trip not found."
            }
            trip.preTripDaysOverride = max(0, min(4, arguments.days))
            let updated = trip
            Task { await model.updateTrip(updated) }
            return "Pre-trip shift now starts \(updated.preTripDaysOverride ?? 0) day(s) before departure."
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        let times = await MainActor.run { PlanAssistant.keyTimesSummary(tripID: tripID, model: model) }
        return summary + " " + times
    }
}

@available(iOS 26.0, *)
struct MarkActionTool: Tool {
    let model: AppModel
    let tripID: UUID
    let onTool: @Sendable (String) async -> Void

    let name = "markPlanAction"
    let description = """
    Mark a plan step as done or skipped when the traveler says they did it or \
    can't do it. Match the step by (part of) its title, e.g. "daylight" or "caffeine".
    """

    @Generable
    struct Arguments {
        @Guide(description: "A distinctive word from the step's title")
        var titleContains: String
        @Guide(description: "done or skipped")
        var status: String
    }

    func call(arguments: Arguments) async throws -> String {
        await onTool("markPlanAction")
        let result: String = await MainActor.run {
            guard let trip = model.state.trips.first(where: { $0.id == tripID }),
                  let plan = model.plan(for: trip) else { return "Trip not found." }
            let needle = arguments.titleContains.lowercased()
            let now = model.deps.now()
            guard let action = plan.actions
                .filter({ $0.completion == .pending })
                .sorted(by: { abs($0.window.start.timeIntervalSince(now)) < abs($1.window.start.timeIntervalSince(now)) })
                .first(where: { $0.title.lowercased().contains(needle) }) else {
                return "No pending step matches “\(arguments.titleContains)”."
            }
            let completion: CompletionState = arguments.status.lowercased() == "done" ? .done : .notPossible
            let matched = action
            Task { await model.setCompletion(completion, for: matched, in: trip) }
            return "Marked “\(matched.title)” as \(arguments.status.lowercased())."
        }
        return result
    }
}

#else

/// Older toolchain: the assistant does not exist.
enum PlanAssistant {
    static var isSupported: Bool { false }
}

#endif
