//
//  ContentView.swift
//  BonsaiChess
//

import SwiftUI
import ChessKit

private struct PuzzleResponse: Decodable {
    let id: Int
    let fen: String
    let expectedMoves: String
    let elo: Int?
}

private struct ParsedMove {
    let moveNumber: Int
    let isWhite: Bool
    let san: String
}

private struct MoveRow {
    let moveNumber: Int
    let whiteInputIndex: Int?
    let blackInputIndex: Int?
}

struct ContentView: View {
    @EnvironmentObject var session: UserSession

    @State private var puzzleFEN: String?
    @State private var expectedMoves: String?
    @State private var currentPuzzleId: Int?
    @State private var position: Position?
    @State private var moveInputs: [String] = []
    @State private var feedback: String = ""
    @State private var feedbackColor: Color = .primary
    @State private var menuVisible = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var isAnimatingSolution = false
    @State private var displayPosition: Position?
    @State private var animatingMove: AnimatingMove?

    private var parsedMoves: [ParsedMove] {
        guard let moves = expectedMoves, !moves.isEmpty else { return [] }
        return Self.parsePGN(moves)
    }

    private var expectedSANs: [String] { parsedMoves.map(\.san) }
    private var moveRows: [MoveRow] { Self.buildMoveRows(parsedMoves) }

    private var toPlayLabel: String {
        guard let first = parsedMoves.first else {
            guard let fen = puzzleFEN else { return "White to play" }
            let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
            return parts.count > 1 && parts[1] == "b" ? "Black to play" : "White to play"
        }
        return first.isWhite ? "White to play" : "Black to play"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if loading {
                        ProgressView("Loading puzzle…")
                            .padding()
                    } else if let error = loadError {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") { fetchPuzzle() }
                            .buttonStyle(.bordered)
                    } else if let position {
                        ChessBoardView(
                            position: isAnimatingSolution ? (displayPosition ?? position) : position,
                            animatingMove: animatingMove
                        )
                        .frame(width: 400, height: 400)
                    } else if puzzleFEN != nil {
                        Text("Invalid FEN")
                            .foregroundStyle(.secondary)
                    }

                    if loadError == nil && !loading && expectedMoves != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(toPlayLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(moveRows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 12) {
                                    Text("\(row.moveNumber)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    if let whiteIndex = row.whiteInputIndex {
                                        TextField("", text: bindingForMove(at: whiteIndex))
                                            .textFieldStyle(.roundedBorder)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .padding(8)
                                    }
                                    if let blackIndex = row.blackInputIndex {
                                        TextField("", text: bindingForMove(at: blackIndex))
                                            .textFieldStyle(.roundedBorder)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .padding(8)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                        Button("Check answer") {
                            checkAnswer()
                        }
                        .buttonStyle(.borderedProminent)

                        if !feedback.isEmpty {
                            Text(feedback)
                                .foregroundStyle(feedbackColor)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        menuVisible = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if let elo = session.currentUser?.elo {
                            Text("\(elo)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("BonsaiChess")
                            .font(.headline)
                    }
                }
            }
            .sheet(isPresented: $menuVisible) {
                MenuView(isPresented: $menuVisible)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let fromLeft = value.startLocation.x < 40
                        let rightSwipe = value.translation.width > 70
                        let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height)
                        if fromLeft && rightSwipe && mostlyHorizontal {
                            menuVisible = true
                        }
                    }
            )
            .onAppear {
                if puzzleFEN == nil && !loading {
                    fetchPuzzle()
                }
            }
        }
    }

    private static func parsePGN(_ pgn: String) -> [ParsedMove] {
        let tokens = pgn.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var moves: [ParsedMove] = []
        var moveNumber = 1
        var expectWhite = true

        for token in tokens {
            if token.hasSuffix(".") && token.dropLast().allSatisfy(\.isNumber), let number = Int(token.dropLast()) {
                moveNumber = number
                expectWhite = true
                continue
            }
            if token == ".." || token == "..." {
                expectWhite = false
                continue
            }
            if token.contains(where: \.isLetter) {
                moves.append(ParsedMove(moveNumber: moveNumber, isWhite: expectWhite, san: token))
                expectWhite.toggle()
            }
        }
        return moves
    }

    private static func buildMoveRows(_ parsed: [ParsedMove]) -> [MoveRow] {
        var inputIndex = 0
        var rowsByNumber: [Int: (white: Int?, black: Int?)] = [:]
        for move in parsed {
            var pair = rowsByNumber[move.moveNumber] ?? (nil, nil)
            if move.isWhite {
                pair.white = inputIndex
            } else {
                pair.black = inputIndex
            }
            rowsByNumber[move.moveNumber] = pair
            inputIndex += 1
        }
        return rowsByNumber.sorted(by: { $0.key < $1.key }).map {
            MoveRow(moveNumber: $0.key, whiteInputIndex: $0.value.white, blackInputIndex: $0.value.black)
        }
    }

    private func fetchPuzzle() {
        loading = true
        loadError = nil
        guard let url = URL(string: UserSession.serverURL + "/api/puzzle") else {
            loadError = "Invalid server URL"
            loading = false
            return
        }
        var request = URLRequest(url: url)
        session.addAuthHeader(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                loading = false
                if let error = error {
                    loadError = "Cannot reach server: \(error.localizedDescription). Is the puzzle server running at \(UserSession.serverURL)?"
                    return
                }
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    loadError = statusCode > 0 ? "Server error (\(statusCode))" : "Server error or no data. Is the puzzle server running at \(UserSession.serverURL)?"
                    return
                }
                do {
                    let puzzle = try JSONDecoder().decode(PuzzleResponse.self, from: data)
                    currentPuzzleId = puzzle.id
                    puzzleFEN = puzzle.fen
                    expectedMoves = puzzle.expectedMoves
                    moveInputs = Array(repeating: "", count: Self.parsePGN(puzzle.expectedMoves).count)
                    feedback = ""
                    isAnimatingSolution = false
                    displayPosition = nil
                    animatingMove = nil
                    loadPosition()
                } catch {
                    loadError = "Invalid response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func loadPosition() {
        guard let fen = puzzleFEN else { return }
        position = Position(fen: fen)
    }

    private func bindingForMove(at index: Int) -> Binding<String> {
        Binding(
            get: { index < moveInputs.count ? moveInputs[index] : "" },
            set: { newValue in
                if index < moveInputs.count {
                    moveInputs[index] = newValue
                }
            }
        )
    }

    private func checkAnswer() {
        guard let fen = puzzleFEN,
              let startPosition = Position(fen: fen),
              let puzzleId = currentPuzzleId else {
            feedback = "Invalid puzzle position."
            feedbackColor = .red
            return
        }

        let userMoves = moveInputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        Task {
            guard let result = await session.submitPuzzleSolution(puzzleId: puzzleId, moves: userMoves) else {
                await MainActor.run {
                    feedback = "Cannot reach server. Is it running at \(UserSession.serverURL)?"
                    feedbackColor = .red
                }
                return
            }

            await MainActor.run {
                if result.correct {
                    feedback = "Correct! Well done."
                    feedbackColor = .green
                } else {
                    feedback = result.error ?? "Incorrect. Try again."
                    feedbackColor = .red
                    return
                }

                isAnimatingSolution = true
                displayPosition = startPosition
                animatingMove = nil
            }

            var pos = startPosition
            for (i, san) in expectedSANs.enumerated() {
                guard let move = Move(san: san, position: pos),
                      let piece = pos.piece(at: move.start) else { break }
                await MainActor.run {
                    displayPosition = pos
                    animatingMove = AnimatingMove(start: move.start, end: move.end, piece: piece)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                var board = Board(position: pos)
                _ = board.move(pieceAt: move.start, to: move.end)
                pos = board.position
                await MainActor.run {
                    displayPosition = pos
                    animatingMove = nil
                }
                if i < expectedSANs.count - 1 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                fetchPuzzle()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserSession())
}
