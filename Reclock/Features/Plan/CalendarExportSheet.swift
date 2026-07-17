import SwiftUI
import ReclockKit

/// Everything calendar in one sheet: pick which calendar (remembered for next time),
/// put the plan's remaining steps on it, or take them all back off. Reached from the
/// Plan tab's calendar button and from trip details — same sheet, same behavior.
struct CalendarExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var calendars: [ExportCalendar] = []
    @State private var selectedID: String?
    @State private var accessDenied = false
    @State private var working = false
    @State private var resultLine: String?
    @State private var errorLine: String?

    private var pendingCount: Int {
        guard let plan = model.plan(for: trip) else { return 0 }
        return PlanCalendarEvents.requests(trip: trip, plan: plan, now: model.deps.now()).count
    }

    var body: some View {
        NavigationStack {
            Form {
                if accessDenied {
                    Section {
                        Label("Calendar access is off", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } footer: {
                        Text("Allow calendar access for Reclock in iOS Settings, then come back — nothing else is needed.")
                    }
                } else {
                    Section {
                        ForEach(calendars) { calendar in
                            Button {
                                Haptics.selection()
                                selectedID = calendar.id
                            } label: {
                                HStack {
                                    Text(calendar.title)
                                        .foregroundStyle(Theme.textPrimary)
                                    if calendar.isDefault {
                                        Text("Default")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    if calendar.id == selectedID {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.accentDeep)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Which calendar?")
                    } footer: {
                        Text("Remembered for next time.")
                    }

                    Section {
                        Button {
                            addToCalendar()
                        } label: {
                            Label(
                                pendingCount == 0
                                    ? "Nothing left to add"
                                    : "Add \(pendingCount) step\(pendingCount == 1 ? "" : "s") to my calendar",
                                systemImage: "calendar.badge.plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(working || pendingCount == 0 || selectedID == nil)

                        Button(role: .destructive) {
                            removeFromCalendar()
                        } label: {
                            Label("Remove my plan from Calendar", systemImage: "calendar.badge.minus")
                        }
                        .disabled(working)
                    } footer: {
                        Text("Events are marked Free, with no alerts — Reclock's own reminders handle the timing. Every event links straight back to this plan. Re-adding replaces instead of duplicating.")
                    }

                    if let resultLine {
                        Section {
                            Label(resultLine, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                        }
                    }
                    if let errorLine {
                        Section {
                            Label(errorLine, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
            }
            .navigationTitle("My calendar")
            .tint(Theme.accentDeep)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCalendars() }
        }
    }

    private func loadCalendars() async {
        let found = await model.deps.calendarExporter.writableCalendars()
        withAnimation(Theme.Anim.gentle) {
            calendars = found
            accessDenied = found.isEmpty
        }
        let remembered = model.state.settings.exportCalendarID
        selectedID = found.first { $0.id == remembered }?.id
            ?? found.first { $0.isDefault }?.id
            ?? found.first?.id
    }

    private func addToCalendar() {
        guard let plan = model.plan(for: trip) else { return }
        working = true
        Task {
            defer { working = false }
            errorLine = nil
            let requests = PlanCalendarEvents.requests(trip: trip, plan: plan, now: model.deps.now())
            let count = await model.deps.calendarExporter.export(
                requests, tripID: trip.id, calendarID: selectedID
            )
            guard let count else {
                // nil can also mean "the write itself failed" (iCloud hiccup, calendar
                // gone) — with a chooser full of calendars, access clearly isn't off.
                if calendars.isEmpty {
                    accessDenied = true
                } else {
                    errorLine = "That didn't save — try again in a moment."
                }
                return
            }
            Haptics.success()
            withAnimation(Theme.Anim.spring) {
                resultLine = "Added \(count) event\(count == 1 ? "" : "s")."
            }
            var settings = model.state.settings
            settings.exportCalendarID = selectedID
            await model.updateSettings(settings)
            // Let the confirmation land, then close and celebrate on the plan.
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
            withAnimation(Theme.Anim.spring) {
                model.celebration = .calendarExported(count: count)
            }
        }
    }

    private func removeFromCalendar() {
        working = true
        Task {
            defer { working = false }
            errorLine = nil
            let count = await model.deps.calendarExporter.removeAll(tripID: trip.id)
            guard let count else {
                if calendars.isEmpty {
                    accessDenied = true
                } else {
                    errorLine = "That didn't work — try again in a moment."
                }
                return
            }
            Haptics.soft()
            withAnimation(Theme.Anim.spring) {
                resultLine = count == 0
                    ? "Nothing of this plan was on your calendar."
                    : "Removed \(count) event\(count == 1 ? "" : "s")."
            }
        }
    }
}
