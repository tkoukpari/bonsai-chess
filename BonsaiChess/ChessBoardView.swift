//
//  ChessBoardView.swift
//  BonsaiChess
//

import SwiftUI
import ChessKit

struct AnimatingMove {
    let start: Square
    let end: Square
    let piece: Piece
}

struct ChessBoardView: View {
    let position: Position
    var animatingMove: AnimatingMove?
    var pieceOpacity: Double = 1

    @State private var moveAnimationProgress: CGFloat = 0

    private let lightSquare = Color(red: 0.94, green: 0.92, blue: 0.84)
    private let darkSquare = Color(red: 0.40, green: 0.55, blue: 0.35)
    private let borderColor = Color(red: 0.25, green: 0.22, blue: 0.20)

    private let ranksTopToBottom = (1...8).reversed().map { $0 }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cellSize = side / 8
            let pieceSize = max(24, min(48, cellSize * 0.85))

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(ranksTopToBottom.enumerated()), id: \.offset) { _, rank in
                        HStack(spacing: 0) {
                            ForEach(Square.File.allCases, id: \.self) { file in
                                squareViewForTransition(
                                    rank: rank,
                                    file: file,
                                    cellSize: cellSize,
                                    pieceSize: pieceSize
                                )
                            }
                        }
                    }
                }

                if let anim = animatingMove {
                    animatingPieceOverlay(anim: anim, cellSize: cellSize, pieceSize: pieceSize)
                }
            }
            .frame(width: side, height: side)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(borderColor, lineWidth: 2))
            .drawingGroup()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func animatingPieceOverlay(anim: AnimatingMove, cellSize: CGFloat, pieceSize: CGFloat) -> some View {
        let start = squareCenter(anim.start, cellSize: cellSize)
        let end = squareCenter(anim.end, cellSize: cellSize)
        let x = start.x + (end.x - start.x) * moveAnimationProgress
        let y = start.y + (end.y - start.y) * moveAnimationProgress

        Image(pieceImageName(anim.piece))
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pieceSize, height: pieceSize)
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            .position(x: x, y: y)
            .onChange(of: anim.start.file.rawValue + String(anim.start.rank.value) + anim.end.file.rawValue + String(anim.end.rank.value)) {
                moveAnimationProgress = 0
                withAnimation(.easeInOut(duration: 0.55)) {
                    moveAnimationProgress = 1
                }
            }
            .onAppear {
                moveAnimationProgress = 0
                withAnimation(.easeInOut(duration: 0.55)) {
                    moveAnimationProgress = 1
                }
            }
    }

    private func squareCenter(_ square: Square, cellSize: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let fileIndex = CGFloat(Array(Square.File.allCases).firstIndex(where: { $0.rawValue == square.file.rawValue }) ?? 0)
        let rowIndex = CGFloat(ranksTopToBottom.firstIndex(of: square.rank.value) ?? 0)
        return ((fileIndex + 0.5) * cellSize, (rowIndex + 0.5) * cellSize)
    }

    private func squareViewForTransition(rank: Int, file: Square.File, cellSize: CGFloat, pieceSize: CGFloat) -> some View {
        let square = Square("\(file.rawValue)\(rank)")
        let piece = position.piece(at: square)
        let hidePiece = animatingMove.map { $0.start.file == square.file && $0.start.rank == square.rank } ?? false
        return squareView(square: square, piece: hidePiece ? nil : piece, pieceSize: pieceSize)
            .frame(width: cellSize, height: cellSize)
    }

    @ViewBuilder
    private func squareView(square: Square, piece: Piece?, pieceSize: CGFloat) -> some View {
        let isLight = (square.file.number + square.rank.value) % 2 == 1
        ZStack {
            Rectangle()
                .fill(isLight ? lightSquare : darkSquare)
            if let piece {
                Image(pieceImageName(piece))
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: pieceSize, height: pieceSize)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .opacity(pieceOpacity)
            }
        }
    }

    private func pieceImageName(_ piece: Piece) -> String {
        let colorPrefix = piece.color == .white ? "w" : "b"
        switch piece.kind {
        case .pawn: return "\(colorPrefix)P"
        case .knight: return "\(colorPrefix)N"
        case .bishop: return "\(colorPrefix)B"
        case .rook: return "\(colorPrefix)R"
        case .queen: return "\(colorPrefix)Q"
        case .king: return "\(colorPrefix)K"
        }
    }
}

#Preview {
    ChessBoardView(position: .standard)
        .padding()
}
