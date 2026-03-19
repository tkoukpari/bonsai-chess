#!/usr/bin/env python3
"""
Import puzzles from Lichess database (https://database.lichess.org).
Downloads lichess_db_puzzle.csv.zst, samples puzzles in a rating range, converts
to BonsaiChess format, and seeds the puzzles table.

Usage:
    DATABASE_URL=postgresql://... python import_lichess_puzzles.py [--max-puzzles 10000]
"""

import csv
import io
import os
import ssl
import sys
import time
import urllib.request

import certifi
import psycopg2
from psycopg2.extras import execute_values
import zstandard

try:
    import chess
except ImportError:
    print("Run: pip install python-chess")
    sys.exit(1)

DATABASE_URL = os.environ["DATABASE_URL"]
LICHESS_PUZZLE_URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"


def build_pgn(board: chess.Board, uci_solution: list[str]) -> str:
    """
    Convert solution UCI moves to PGN.
    uci_solution: list of UCI moves (first is our move, then their response, etc.)
    """
    parts: list[str] = []
    move_number = board.fullmove_number

    for i, uci in enumerate(uci_solution):
        try:
            move = chess.Move.from_uci(uci)
        except chess.InvalidMoveError:
            break
        if move not in board.legal_moves:
            break

        san = board.san(move)
        is_white = board.turn == chess.WHITE

        if is_white:
            parts.append(f"{move_number}. {san}")
        else:
            if i == 0:
                parts.append(f"{move_number}. ... {san}")  # Black's first move
            else:
                parts.append(san)
            move_number += 1

        board.push(move)

    return " ".join(parts)


def convert_lichess_to_bonsai(
    lichess_fen: str, lichess_moves: str, rating: int
) -> tuple[str, str, int] | None:
    """
    Convert Lichess puzzle format to BonsaiChess format.
    Returns (fen, expected_moves, elo) or None if conversion fails.
    """
    moves = lichess_moves.strip().split()
    if len(moves) < 5:
        return None

    try:
        board = chess.Board(lichess_fen)
    except (ValueError, AssertionError):
        return None

    # First move is opponent's; apply it to get puzzle position
    try:
        opp_move = chess.Move.from_uci(moves[0])
    except chess.InvalidMoveError:
        return None
    if opp_move not in board.legal_moves:
        return None
    board.push(opp_move)

    puzzle_fen = board.fen()
    solution_uci = moves[1:]
    if not solution_uci:
        return None

    try:
        pgn = build_pgn(chess.Board(puzzle_fen), solution_uci)
    except Exception:
        return None
    if not pgn.strip():
        return None

    return (puzzle_fen, pgn, rating)


def stream_csv_from_zst(url: str):
    """Stream decompressed CSV lines from a .zst URL."""
    dctx = zstandard.ZstdDecompressor()
    ctx = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(url, timeout=120, context=ctx) as resp:
        reader = dctx.stream_reader(resp)
        for line in io.TextIOWrapper(reader, encoding="utf-8", errors="replace"):
            yield line


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Import Lichess puzzles into BonsaiChess")
    parser.add_argument("--max-puzzles", type=int, default=10000, help="Max puzzles to import")
    parser.add_argument("--rating-min", type=int, default=1800, help="Min puzzle rating")
    parser.add_argument("--sample-every", type=int, default=10, help="Take every Nth puzzle in range (lower = more puzzles, 10 = ~10k from ~100k scanned)")
    args = parser.parse_args()

    print("Downloading and decompressing Lichess puzzle database...")
    print("(This may take a few minutes...)")
    t0 = time.time()

    collected: list[tuple[str, str, int]] = []
    in_range = 0
    lines_read = 0

    for line in stream_csv_from_zst(LICHESS_PUZZLE_URL):
        if len(collected) >= args.max_puzzles:
            break

        lines_read += 1
        if lines_read % 50000 == 0:
            print(f"  Scanned {lines_read:,} lines, collected {len(collected):,} puzzles...")

        row = next(csv.reader(io.StringIO(line)), None)
        if not row or len(row) < 4:
            continue

        puzzle_id, fen, moves_str, rating_str = row[0], row[1], row[2], row[3]
        try:
            rating = int(rating_str)
        except ValueError:
            continue

        if rating < args.rating_min:
            continue

        in_range += 1
        if in_range % args.sample_every != 0:
            continue

        result = convert_lichess_to_bonsai(fen, moves_str, rating)
        if result:
            collected.append(result)
            if len(collected) % 1000 == 0:
                print(f"  Collected {len(collected):,} puzzles...")

    elapsed = time.time() - t0
    print(f"Collected {len(collected):,} puzzles in {elapsed:.1f}s. Seeding database...")

    t1 = time.time()
    print("  Connecting to database...")
    conn = psycopg2.connect(DATABASE_URL)
    try:
        cur = conn.cursor()
        print("  Deleting existing puzzles and attempts...")
        cur.execute("DELETE FROM user_puzzle_attempts")
        cur.execute("DELETE FROM puzzles")
        print(f"  Inserting {len(collected):,} puzzles (batches of 1000)...")
        for i in range(0, len(collected), 1000):
            batch = collected[i : i + 1000]
            execute_values(
                cur,
                "INSERT INTO puzzles (fen, expected_moves, elo) VALUES %s",
                batch,
                page_size=1000,
            )
            print(f"    Inserted {min(i + 1000, len(collected)):,} / {len(collected):,}")
        print("  Committing...")
        conn.commit()
        cur.execute("SELECT COUNT(*) FROM puzzles")
        count = cur.fetchone()[0]
        elapsed_db = time.time() - t1
        print(f"Seeded {count:,} puzzles in {elapsed_db:.1f}s. Done.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
