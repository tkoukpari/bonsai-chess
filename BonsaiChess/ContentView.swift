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

private enum TransitionPhase { case fadeOut, fadeIn }

struct ContentView: View {
    @EnvironmentObject var session: UserSession

    @State private var puzzleFEN: String?
    @State private var expectedMoves: String?
    @State private var currentPuzzleId: Int?
    @State private var position: Position?
    @State private var moveInputs: [String] = []
    @State private var feedback: String = ""
    @State private var menuVisible = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var isAnimatingSolution = false
    @State private var displayPosition: Position?
    @State private var animatingMove: AnimatingMove?
    @State private var transitionPhase: TransitionPhase?
    @State private var transitionFromPosition: Position?
    @State private var transitionToPosition: Position?
    @State private var boardTransitionProgress: CGFloat = 1
    @State private var pendingPuzzle: (id: Int, fen: String, moves: String)?
    @State private var checkAnswerLocked = false
    @FocusState private var focusedInputIndex: Int?

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
                    if loading && position == nil {
                        ProgressView("Loading puzzle…")
                            .padding()
                    } else if let error = loadError {
                        Text(error)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") { fetchPuzzle() }
                            .buttonStyle(.bordered)
                    } else if let position {
                        transitionBoardView(position: position)
                    } else if puzzleFEN != nil {
                        Text("Invalid FEN")
                            .foregroundStyle(.secondary)
                    }

                    if loadError == nil && (expectedMoves != nil || position != nil) {
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
                                                .focused($focusedInputIndex, equals: whiteIndex)
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
                                                .focused($focusedInputIndex, equals: blackIndex)
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
                        .animation(.easeInOut(duration: 0.35), value: currentPuzzleId)

                        Button("Check answer") {
                            checkAnswer()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checkAnswerLocked)

                        if !feedback.isEmpty {
                            Text(feedback)
                                .foregroundStyle(.primary)
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
            .onChange(of: currentPuzzleId) {
                if currentPuzzleId != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        focusedInputIndex = 0
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transitionBoardView(position: Position) -> some View {
        let (displayPos, opacity): (Position, Double) = {
            if let phase = transitionPhase {
                switch phase {
                case .fadeOut:
                    if let from = transitionFromPosition {
                        return (from, 1 - boardTransitionProgress)
                    }
                case .fadeIn:
                    if let to = transitionToPosition {
                        return (to, boardTransitionProgress)
                    }
                }
            }
            return (isAnimatingSolution ? (displayPosition ?? position) : position, 1)
        }()
        ChessBoardView(
            position: displayPos,
            animatingMove: transitionPhase == nil ? animatingMove : nil,
            pieceOpacity: opacity
        )
        .frame(width: 400, height: 400)
        .animation(.easeInOut(duration: 0.4), value: boardTransitionProgress)
        .animation(.easeInOut(duration: 0.4), value: transitionPhase)
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
            var indices = rowsByNumber[move.moveNumber] ?? (nil, nil)
            if move.isWhite {
                indices.white = inputIndex
            } else {
                indices.black = inputIndex
            }
            rowsByNumber[move.moveNumber] = indices
            inputIndex += 1
        }
        return rowsByNumber.sorted(by: { $0.key < $1.key }).map {
            MoveRow(moveNumber: $0.key, whiteInputIndex: $0.value.white, blackInputIndex: $0.value.black)
        }
    }

    private func fetchPuzzle(transitionFrom finalPosition: Position? = nil) {
        let isTransition = finalPosition != nil
        if !isTransition {
            loading = true
        }
        loadError = nil
        guard let url = URL(string: UserSession.serverURL + "/api/puzzle") else {
            loadError = "Invalid server URL"
            loading = false
            if isTransition { checkAnswerLocked = false }
            return
        }
        var request = URLRequest(url: url)
        session.addAuthHeader(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if !isTransition { loading = false }
                if let error = error {
                    loadError = "Cannot reach server."
                    if isTransition { checkAnswerLocked = false }
                    return
                }
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    loadError = statusCode > 0 ? "Server error (\(statusCode))" : "Server error or no data. Is the puzzle server running at \(UserSession.serverURL)?"
                    if isTransition { checkAnswerLocked = false }
                    return
                }
                do {
                    let puzzle = try JSONDecoder().decode(PuzzleResponse.self, from: data)
                    let newPos = Position(fen: puzzle.fen)

                    if isTransition, let from = finalPosition {
                        pendingPuzzle = (puzzle.id, puzzle.fen, puzzle.expectedMoves)
                        transitionFromPosition = from
                        transitionToPosition = newPos
                        transitionPhase = .fadeOut
                        isAnimatingSolution = false
                        displayPosition = nil
                        animatingMove = nil
                        boardTransitionProgress = 0
                        withAnimation(.easeInOut(duration: 0.4)) {
                            boardTransitionProgress = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            applyPendingPuzzleAndFadeIn()
                        }
                    } else {
                        currentPuzzleId = puzzle.id
                        puzzleFEN = puzzle.fen
                        expectedMoves = puzzle.expectedMoves
                        moveInputs = Array(repeating: "", count: Self.parsePGN(puzzle.expectedMoves).count)
                        feedback = ""
                        animatingMove = nil
                        loadPosition()
                        transitionPhase = nil
                        transitionFromPosition = nil
                        transitionToPosition = nil
                        pendingPuzzle = nil
                        boardTransitionProgress = 1
                        isAnimatingSolution = false
                        displayPosition = nil
                    }
                } catch {
                    loadError = "Invalid response: \(error.localizedDescription)"
                    if isTransition { checkAnswerLocked = false }
                }
            }
        }.resume()
    }

    private func applyPendingPuzzleAndFadeIn() {
        guard let pending = pendingPuzzle else { return }
        currentPuzzleId = pending.id
        puzzleFEN = pending.fen
        expectedMoves = pending.moves
        moveInputs = Array(repeating: "", count: Self.parsePGN(pending.moves).count)
        feedback = ""
        loadPosition()
        transitionFromPosition = nil
        transitionToPosition = position
        transitionPhase = .fadeIn
        pendingPuzzle = nil
        boardTransitionProgress = 0
        withAnimation(.easeInOut(duration: 0.4)) {
            boardTransitionProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            transitionPhase = nil
            transitionToPosition = nil
            checkAnswerLocked = false
        }
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
            return
        }

        checkAnswerLocked = true

        let userMoves = moveInputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        Task {
            guard let result = await session.submitPuzzleSolution(puzzleId: puzzleId, moves: userMoves) else {
                await MainActor.run {
                    feedback = "Cannot reach server."
                    checkAnswerLocked = false
                }
                return
            }

            guard result.correct else {
                await MainActor.run {
                    feedback = result.error ?? "Incorrect. Try again."
                    checkAnswerLocked = false
                }
                return
            }

            await MainActor.run {
                feedback = "Correct! Well done."
                isAnimatingSolution = true
                displayPosition = startPosition
                animatingMove = nil
            }

            var currentPos = startPosition
            for (i, san) in expectedSANs.enumerated() {
                guard let move = Move(san: san, position: currentPos) else { break }
                var board = Board(position: currentPos)
                guard board.move(pieceAt: move.start, to: move.end) != nil else { break }
                let newPos = board.position
                let piece = newPos.piece(at: move.end) ?? currentPos.piece(at: move.start)!
                await MainActor.run {
                    displayPosition = currentPos
                    animatingMove = AnimatingMove(start: move.start, end: move.end, piece: piece)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                currentPos = newPos
                await MainActor.run {
                    displayPosition = currentPos
                    animatingMove = nil
                }
                if i < expectedSANs.count - 1 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let finalPos = currentPos
            await MainActor.run {
                fetchPuzzle(transitionFrom: finalPos)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserSession())
}
