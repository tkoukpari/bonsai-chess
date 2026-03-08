//
//  UserSession.swift
//  BonsaiChess
//

import Foundation

struct User: Codable, Identifiable {
    let id: Int
    var username: String
    var email: String
    var elo: Int
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

@MainActor
final class UserSession: ObservableObject {
    static let serverURL = "http://localhost:8080"

    @Published private(set) var currentUser: User?
    @Published var isLoading = false
    @Published var error: String?

    private let tokenKey = "bonsai_chess_token"
    private let userKey = "bonsai_chess_user"

    init() {
        loadStoredSession()
    }

    var isLoggedIn: Bool { currentUser != nil }

    var token: String? {
        KeychainHelper.load(forKey: tokenKey)
    }

    func addAuthHeader(to request: inout URLRequest) {
        if let authToken = token {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func loadStoredSession() {
        guard let authToken = KeychainHelper.load(forKey: tokenKey),
              let data = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return
        }
        currentUser = user
        Task { await refreshUser() }
    }

    func saveSession(token: String, user: User) {
        KeychainHelper.save(token, forKey: tokenKey)
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    func logout() {
        currentUser = nil
        KeychainHelper.delete(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func login(username: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: Self.serverURL + "/api/auth/login") else {
            error = "Invalid server URL"
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct LoginBody: Encodable {
            let username: String
            let password: String
        }
        req.httpBody = try? JSONEncoder().encode(LoginBody(username: username.trimmingCharacters(in: .whitespaces), password: password))

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                error = "Invalid response"
                return
            }
            guard http.statusCode == 200,
                  let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
                if let err = try? JSONDecoder().decode([String: String].self, from: data), let msg = err["error"] {
                    error = msg
                } else {
                    error = "Could not log in"
                }
                return
            }
            saveSession(token: auth.token, user: auth.user)
        } catch {
            self.error = "Cannot reach server."
        }
    }

    func createAccount(username: String, email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: Self.serverURL + "/api/users") else {
            error = "Invalid server URL"
            return
        }
        struct CreateBody: Encodable {
            let username: String
            let email: String
            let password: String
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(CreateBody(
            username: username.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            password: password
        ))

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                error = "Invalid response"
                return
            }
            if http.statusCode == 409 {
                error = "Username already taken"
                return
            }
            guard (200...299).contains(http.statusCode),
                  let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
                if let err = try? JSONDecoder().decode([String: String].self, from: data), let msg = err["error"] {
                    error = msg
                } else {
                    error = "Could not create account"
                }
                return
            }
            saveSession(token: auth.token, user: auth.user)
        } catch {
            self.error = "Cannot reach server."
        }
    }

    func refreshUser() async {
        guard token != nil else { return }
        guard let url = URL(string: Self.serverURL + "/api/users/me") else { return }

        var req = URLRequest(url: url)
        addAuthHeader(to: &req)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                logout()
                return
            }
            if let updated = try? JSONDecoder().decode(User.self, from: data) {
                currentUser = updated
                if let encoded = try? JSONEncoder().encode(updated) {
                    UserDefaults.standard.set(encoded, forKey: userKey)
                }
            }
        } catch {
            // Silently fail
        }
    }

    func deleteAccount() async {
        guard let url = URL(string: Self.serverURL + "/api/users/me") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        addAuthHeader(to: &req)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                logout()
            } else if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                logout()
            }
        } catch {
            self.error = "Could not delete account: \(error.localizedDescription)"
        }
    }

    struct PuzzleResult {
        let correct: Bool
        let error: String?
        let elo: Int?
        let eloChange: Int?
    }

    func submitPuzzleSolution(puzzleId: Int, moves: [String]) async -> PuzzleResult? {
        guard let url = URL(string: Self.serverURL + "/api/puzzle/result") else { return nil }

        struct ResultBody: Encodable {
            let puzzle_id: Int
            let moves: [String]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &req)
        req.httpBody = try? JSONEncoder().encode(ResultBody(puzzle_id: puzzleId, moves: moves))

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let correct = json["correct"] as? Bool else {
                return nil
            }
            let error = json["error"] as? String
            let elo = json["elo"] as? Int
            let eloChange = json["eloChange"] as? Int
            if let user = currentUser, let newElo = elo {
                var updated = user
                updated.elo = newElo
                currentUser = updated
                if let encoded = try? JSONEncoder().encode(updated) {
                    UserDefaults.standard.set(encoded, forKey: userKey)
                }
            }
            return PuzzleResult(correct: correct, error: error, elo: elo, eloChange: eloChange)
        } catch {
            return nil
        }
    }
}
