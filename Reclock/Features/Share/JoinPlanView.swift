import SwiftUI
import AuthenticationServices
import ReclockKit

/// Join a friend's shared plan: enter (or arrive with) a code, preview the trip,
/// one tap to add it. Requires sign-in so your checkmarks can sync back.
struct JoinPlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var prefilledCode: String = ""
    var onFinished: (() -> Void)?

    @State private var code = ""
    @State private var isFetching = false
    @State private var fetched: FetchedSharedPlan?
    @State private var errorText: String?
    @State private var isJoining = false

    var body: some View {
        Form {
            if !model.auth.isSignedIn {
                Section {
                    Text("Sign in first — that's how your buddies see your checkmarks (and you see theirs).")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    SignInWithAppleButton(.signIn) { request in
                        model.auth.prepare(request)
                    } onCompletion: { result in
                        Task {
                            if await model.auth.complete(result) {
                                Haptics.success()
                                await model.handleSignedIn()
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                        if model.auth.googleAvailable {
                        GoogleSignInButton {
                            Task {
                                if await model.auth.signInWithGoogle() {
                                        Haptics.success()
                                        await model.handleSignedIn()
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            } else {
                Section {
                    TextField("Invite code (e.g. Q7MPX2)", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                    Button {
                        Task { await find() }
                    } label: {
                        if isFetching {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Find the trip", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || isFetching)
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .transition(.opacity)
                    }
                } footer: {
                    Text("Your buddy finds the code on their trip page under Travel buddies.")
                }

                if let fetched {
                    Section("Their trip") {
                        HStack {
                            Text("\(fetched.trip.origin) → \(fetched.trip.destination)")
                                .font(.title3.weight(.heavy))
                                .fontDesign(.rounded)
                            Spacer()
                        }
                        if let departure = fetched.trip.segments.first?.departure {
                            LabeledContent(
                                "Departs",
                                value: TimeFormat.dayDate(departure, zone: fetched.trip.homeZone.resolved)
                            )
                        }
                        Button {
                            Task { await join(fetched) }
                        } label: {
                            if isJoining {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Add to my plans").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isJoining)
                    }
                }
            }
        }
        .navigationTitle("Join a friend's trip")
        .tint(Theme.accentDeep)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.auth.isSignedIn) { _, signedIn in
            // Arriving from an invite link signed out: after sign-in, keep going.
            if signedIn && !code.trimmingCharacters(in: .whitespaces).isEmpty {
                Task { await find() }
            }
        }
        .onAppear {
            if code.isEmpty { code = prefilledCode }
            // Arriving via invite link with a session ready: look it up immediately.
            if !prefilledCode.isEmpty && model.auth.isSignedIn {
                Task { await find() }
            }
        }
    }

    private func find() async {
        isFetching = true
        errorText = nil
        fetched = nil
        defer { isFetching = false }
        if let plan = await model.fetchSharedPlan(code: code) {
            withAnimation(Theme.Anim.spring) { fetched = plan }
            Haptics.success()
        } else {
            withAnimation(Theme.Anim.spring) {
                errorText = "No trip found for that code. Double-check it with your buddy."
            }
        }
    }

    private func join(_ plan: FetchedSharedPlan) async {
        isJoining = true
        defer { isJoining = false }
        if await model.acceptSharedPlan(plan) {
            Haptics.success()
            onFinished?()
            dismiss()
        } else {
            withAnimation(Theme.Anim.spring) {
                errorText = "Couldn't join right now — check your connection and try again."
            }
        }
    }
}

/// Identifiable wrapper so a deep-linked code can drive a sheet.
struct PendingJoinCode: Identifiable, Equatable {
    let code: String
    var id: String { code }
}
