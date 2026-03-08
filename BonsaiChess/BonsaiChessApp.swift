//
//  BonsaiChessApp.swift
//  BonsaiChess
//

import SwiftUI

@main
struct BonsaiChessApp: App {
    @StateObject private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
