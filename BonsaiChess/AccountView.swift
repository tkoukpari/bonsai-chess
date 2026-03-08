//
//  AccountView.swift
//  BonsaiChess
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var session: UserSession
    @Binding var isPresented: Bool
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginMode = false

    var body: some View {
        Group {
            if let user = session.currentUser {
                loggedInView(user: user)
            } else {
                createAccountView
            }
        }
        .task {
            await session.refreshUser()
        }
    }

    private func loggedInView(user: User) -> some View {
        List {
            Section("Profile") {
                LabeledContent("Username", value: user.username)
                LabeledContent("Email", value: user.email)
                LabeledContent("Elo", value: "\(user.elo)")
            }
            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("Log out")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete account")
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { isPresented = false }
            }
        }
        .confirmationDialog("Log out?", isPresented: $showLogoutConfirm) {
            Button("Log out", role: .destructive) {
                session.logout()
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress is saved on the server. You can log back in with the same username.")
        }
        .confirmationDialog("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete account", role: .destructive) {
                Task {
                    await session.deleteAccount()
                    isPresented = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all progress. This cannot be undone.")
        }
    }

    private var createAccountView: some View {
        Form {
            if isLoginMode {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Log in")
                }
            } else {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                } header: {
                    Text("Create account")
                } footer: {
                    Text("Username must be unique. Email must be valid. Password must be at least 8 characters.")
                }
            }

            if let error = session.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task {
                        if isLoginMode {
                            await session.login(username: username, password: password)
                        } else {
                            await session.createAccount(username: username, email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        if session.isLoading {
                            ProgressView()
                                .scaleEffect(0.9)
                        }
                        Text(isLoginMode ? "Log in" : "Create account")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    username.trimmingCharacters(in: .whitespaces).isEmpty ||
                    password.isEmpty ||
                    (!isLoginMode && !isValidEmail(email)) ||
                    (!isLoginMode && password.count < 8) ||
                    session.isLoading
                )
            }

            Section {
                Button {
                    isLoginMode.toggle()
                    password = ""
                    session.error = nil
                } label: {
                    Text(isLoginMode ? "Create new account" : "Already have an account? Log in")
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { isPresented = false }
            }
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else { return false }
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[0].count >= 1 && parts[1].count >= 3 && parts[1].contains(".")
    }
}
