#!/usr/bin/env python3

import io
import os
import ssl
import urllib.request

import certifi
import pandas as pd
import zstandard
from sqlalchemy import create_engine, text
import chess

DATABASE_URL = os.environ["DATABASE_URL"]
LICHESS_PUZZLE_URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"

MAX_PUZZLES = 10_000
MINIMUM_RATING = 1400
CHUNK_SIZE = 50_000


def build_pgn(board, uci_solution):
    parts = []
    move_number = board.fullmove_number

    for i, uci in enumerate(uci_solution):
        move = chess.Move.from_uci(uci)
        san = board.san(move)
        is_white = board.turn == chess.WHITE

        if is_white:
            parts.append(f"{move_number}. {san}")
        else:
            if i == 0:
                parts.append(f"{move_number}. ... {san}")
            else:
                parts.append(san)
            move_number += 1

        board.push(move)

    return " ".join(parts)


def convert_lichess_to_bonsai(lichess_fen, lichess_moves, rating):
    moves = lichess_moves.strip().split()
    board = chess.Board(lichess_fen)
    board.push(chess.Move.from_uci(moves[0]))
    puzzle_fen = board.fen()
    solution_uci = moves[1:]
    pgn = build_pgn(chess.Board(puzzle_fen), solution_uci)
    return puzzle_fen, pgn, rating


def convert_row(row):
    try:
        return convert_lichess_to_bonsai(row["fen"], row["moves"], row["rating"])
    except (ValueError, IndexError, KeyError):
        return None


def stream_csv_from_zst(url):
    dctx = zstandard.ZstdDecompressor()
    ctx = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(url, timeout=120, context=ctx) as resp:
        reader = dctx.stream_reader(resp)
        return io.TextIOWrapper(reader, encoding="utf-8", errors="replace")


def main():
    stream = stream_csv_from_zst(LICHESS_PUZZLE_URL)
    columns = ["puzzle_id", "fen", "moves", "rating"]

    rows = []
    for chunk in pd.read_csv(stream, sep=",", header=None, names=columns, chunksize=CHUNK_SIZE):
        chunk["rating"] = pd.to_numeric(chunk["rating"], errors="coerce")
        chunk = chunk.dropna(subset=["rating"])
        chunk = chunk[chunk["rating"] >= MINIMUM_RATING]
        for _, row in chunk.iterrows():
            result = convert_row(row)
            if result:
                rows.append(result)
            if len(rows) >= MAX_PUZZLES:
                break
        if len(rows) >= MAX_PUZZLES:
            break

    df = pd.DataFrame(rows[:MAX_PUZZLES], columns=["fen", "expected_moves", "elo"])

    url = DATABASE_URL.replace("postgresql://", "postgresql+psycopg2://", 1)
    engine = create_engine(url)
    with engine.connect() as conn:
        conn.execute(text("DELETE FROM user_puzzle_attempts"))
        conn.execute(text("DELETE FROM puzzles"))
        conn.commit()
    df.to_sql("puzzles", engine, if_exists="append", index=False, method="multi", chunksize=1000)


if __name__ == "__main__":
    main()
