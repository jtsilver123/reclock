import SwiftUI
import ReclockKit

#if canImport(FoundationModels)
import FoundationModels

/// "Ask Reclock" — a personal plan assistant. Answers are grounded in the live plan;
/// adjustment requests go through tools that actually rebuild it. Fully on-device.
@available(iOS 26.0, *)
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var isUser: Bool
        var text: String
    }

    @State private var session: LanguageModelSession?
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var isThinking = false

    private let suggestions = [
        "Why light at that time?",
        "Make the plan gentler",
        "I can't sleep before midnight",
        "What matters most today?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            if messages.isEmpty {
                                emptyState
                            }
                            ForEach(messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                            if isThinking && messages.last?.isUser == true {
                                HStack(spacing: Theme.Space.s) {
                                    ProgressView()
                                    Text("Thinking…")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, Theme.Space.m)
                            }
                        }
                        .padding(Theme.Space.m)
                    }
                    .onChange(of: messages) { _, newValue in
                        if let last = newValue.last {
                            withAnimation(Theme.Anim.gentle) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
            .background(Theme.background)
            .navigationTitle("Ask Reclock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if session == nil {
                    session = PlanAssistant.makeSession(trip: trip, model: model)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.18))
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan, on tap")
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ask why a step exists, or tell me what's not working — I can adjust the plan for real. Everything stays on this phone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Space.m)
            .card()

            FlowChips(suggestions: suggestions) { suggestion in
                input = suggestion
                Task { await send() }
            }
        }
    }

    private func bubble(_ message: Message) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: Theme.Space.xl) }
            Text(message.text)
                .font(.callout)
                .foregroundStyle(message.isUser ? Theme.ink : Theme.textPrimary)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isUser ? Theme.accent : Theme.surface)
                )
            if !message.isUser { Spacer(minLength: Theme.Space.xl) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Ask about your plan…", text: $input, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit { Task { await send() } }
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Theme.textSecondary.opacity(0.4) : Theme.accentDeep)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            .accessibilityLabel("Send")
        }
        .padding(Theme.Space.m)
        .background(Theme.background)
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let session, !isThinking else { return }
        input = ""
        Haptics.soft()
        messages.append(Message(isUser: true, text: text))
        isThinking = true
        defer { isThinking = false }
        do {
            var assistantIndex: Int?
            let stream = session.streamResponse(to: text)
            for try await partial in stream {
                let content = partial.content
                if let index = assistantIndex {
                    messages[index].text = content
                } else {
                    messages.append(Message(isUser: false, text: content))
                    assistantIndex = messages.count - 1
                }
            }
            Haptics.soft()
        } catch {
            messages.append(Message(
                isUser: false,
                text: "I couldn't think that one through — mind trying again?"
            ))
        }
    }
}

/// Wrapping chip row for suggested prompts.
@available(iOS 26.0, *)
private struct FlowChips: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    Haptics.selection()
                    onTap(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceSecondary, in: Capsule())
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }
}

/// Home-toolbar entry point: visible only where the on-device model exists.
struct AssistantToolbarButton: View {
    @Environment(AppModel.self) private var model
    @State private var showAssistant = false

    var body: some View {
        if #available(iOS 26.0, *), PlanAssistant.isSupported, let trip = model.activeTrip {
            Button {
                Haptics.soft()
                showAssistant = true
            } label: {
                Image(systemName: "sparkles")
                    .accessibilityLabel("Ask Reclock")
            }
            .sheet(isPresented: $showAssistant) {
                AssistantView(trip: trip)
                    .presentationDetents([.large])
            }
        }
    }
}

#else

/// Older toolchain: no assistant, no button.
struct AssistantToolbarButton: View {
    var body: some View { EmptyView() }
}

#endif
