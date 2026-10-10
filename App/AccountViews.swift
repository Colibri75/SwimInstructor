import AuthenticationServices
import SwiftUI
import SwimInstructorCore

/// "Mit Apple anmelden": holt bei Apple ein Identitätstoken, tauscht es beim Server gegen einen eigenen Token und legt
/// ihn in den Schlüsselbund (`BackendSettings.signIn`). Danach laufen alle Aufrufe wie mit einem Token von Hand.
struct AppleSignInButton: View {
    @EnvironmentObject private var settings: BackendSettings
    @Environment(\.colorScheme) private var colorScheme

    /// Nach erfolgreicher Anmeldung, etwa um gleich einen Plan zu holen.
    var onSignedIn: () -> Void = {}

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.5 : 1)
            if isSigningIn {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Anmeldung läuft …")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = AccountError.invalidIdentity.localizedDescription
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            Task { await signIn(identityToken: identityToken, name: name) }
        case .failure(let error):
            // Abgebrochen: keine Meldung, der Nutzer wollte es so.
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled { return }
            errorMessage = AccountError.invalidIdentity.localizedDescription
        }
    }

    private func signIn(identityToken: String, name: String?) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let session = try await AccountClient(baseURL: settings.baseURL)
                .signInWithApple(identityToken: identityToken, name: name)
            try settings.signIn(session)
            onSignedIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Abschnitt "Konto" der Einstellungen: angemeldet mit Apple (Abmelden, Konto löschen) oder der Knopf zum Anmelden.
struct AccountSection: View {
    @EnvironmentObject private var settings: BackendSettings

    var onSignedIn: () -> Void = {}

    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if settings.hasToken {
                if let name = settings.accountName {
                    Label("Angemeldet als \(name)", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    Label("Mit Server-Token verbunden", systemImage: "key")
                }
                Button("Abmelden") {
                    errorMessage = nil
                    try? settings.signOut()
                }
                if settings.isSignedInWithApple {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        if isDeleting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Konto wird gelöscht …")
                            }
                        } else {
                            Text("Konto löschen")
                        }
                    }
                    .disabled(isDeleting)
                    .confirmationDialog("Konto löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                        Button("Konto und Pläne löschen", role: .destructive) {
                            Task { await deleteAccount() }
                        }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Dein Konto und deine Pläne auf dem Server werden endgültig gelöscht. Deine Daten in Apple Health und deine Einstellungen auf diesem iPhone bleiben.")
                    }
                }
            } else {
                Text("Melde dich an, damit dein Coach Pläne erstellen kann.")
                AppleSignInButton(onSignedIn: onSignedIn)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Konto")
        } footer: {
            Text("Mit deiner Apple-ID meldest du dich beim Server deines Coaches an. Gespeichert werden dort eine Kennung von Apple und, falls du sie teilst, dein Name und deine E-Mail-Adresse.")
        }
    }

    private func deleteAccount() async {
        guard let token = settings.configuration?.token else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await AccountClient(baseURL: settings.baseURL).deleteAccount(token: token)
            try settings.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
