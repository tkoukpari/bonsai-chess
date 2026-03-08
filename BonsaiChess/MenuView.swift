//
//  MenuView.swift
//  BonsaiChess
//

import SwiftUI

struct MenuView: View {
    @EnvironmentObject var session: UserSession
    @Binding var isPresented: Bool
    @State private var showSAN = false
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showAccount = true
                } label: {
                    Label("Account", systemImage: "person.circle")
                }
                Button {
                    showSAN = true
                } label: {
                    Label("SAN (how it works)", systemImage: "doc.text")
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
            .sheet(isPresented: $showSAN) {
                SANReadMeView()
            }
            .sheet(isPresented: $showAccount) {
                NavigationStack {
                    AccountView(isPresented: $showAccount)
                        .environmentObject(session)
                }
            }
        }
    }
}

struct SANReadMeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("SAN (Standard Algebraic Notation)")
                    Text("SAN is how chess moves are written. Each move is one short string:")
                    bullet("Pawns: just the square, e.g. e4, exd5 (e-file pawn captures on d5)")
                    bullet("Pieces: letter then square. K=king, Q=queen, R=rook, B=bishop, N=knight. Examples: Nf3, Bb5, Ke1")
                    bullet("Capture: x between piece (or file for pawns) and square: Nxe5, exd5")
                    bullet("Castling: O-O (kingside), O-O-O (queenside)")
                    bullet("Promotion: add = and the new piece, e.g. e8=Q")
                    bullet("Check: + at the end (optional). Checkmate: # at the end (optional).")
                    Text("Files are a–h (left to right for White). Ranks are 1–8 (White’s back rank is 1). So e4 is the pawn to the e4 square.")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("SAN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Menu") {
    MenuView(isPresented: .constant(true))
        .environmentObject(UserSession())
}
