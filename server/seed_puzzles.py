#!/usr/bin/env python3

import os

import psycopg2

DATABASE_URL = os.environ["DATABASE_URL"]

puzzles = [
    ("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "1. Qxf7#", 600),
    ("6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", "1. Re8#", 650),
    ("r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "1. Qxf7#", 700),
    ("5rk1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", "1. Re8#", 700),
    ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4", "1. Bxf7+ Ke7 2. Bg5#", 800),
    ("r1bqk2r/ppp1bppp/2np1n2/4N3/2B1P3/2NP4/PPP2PPP/R1B1K2R w KQkq - 0 6", "1. Bxf7+ Ke7 2. Nd5#", 900),
    ("r2qkb1r/ppp2ppp/2n1bn2/3pp1B1/3PP3/2N2N2/PPP2PPP/R1BQK2R w KQkq - 0 6", "1. Bxf6 gxf6 2. Nxd5", 1000),
    ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "1. Nxe5 Nxe5 2. d4", 950),
    ("r1bqkb1r/pppp1ppp/2n2n2/4p1B1/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "1. Nxe5 Nxe5 2. Bxf7+", 1000),
    ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4", "1. Ng5 O-O 2. Nxf7 Rxf7 3. Bxf7+", 1050),
    ("r2qkb1r/ppp2ppp/2n1bn2/3pp1B1/3PP3/2N2N2/PPP2PPP/R1BQK2R w KQkq - 0 6", "1. Bg5 O-O 2. Nxd5", 1000),
    ("5rk1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", "1. Re8+ Rf8 2. Rxf8#", 950),
    ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4", "1. Bxf7+ Kxf7 2. Ng5+ Ke8 3. Qf3", 1100),
    ("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "1. Qh5 Nc6 2. Bc4 Nf6 3. Qxf7#", 750),
    ("2kr4/ppp2ppp/8/8/8/8/PPP2PPP/2KR4 w - - 0 1", "1. Rd8+ Rxd8 2. Rxd8#", 800),
    ("r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 3", "1. .. Nd4 2. Bxd4 exd4", 1100),
    ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "1. Bxf7+ Kxf7 2. Ng5+ Ke8 3. Qf3", 1100),
]


def main():
    conn = psycopg2.connect(DATABASE_URL)
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM user_puzzle_attempts")
        cur.execute("DELETE FROM puzzles")
        for fen, expected_moves, elo in puzzles:
            cur.execute(
                "INSERT INTO puzzles (fen, expected_moves, elo) VALUES (%s, %s, %s)",
                (fen, expected_moves, elo),
            )
        conn.commit()
        cur.execute("SELECT COUNT(*) FROM puzzles")
        count = cur.fetchone()[0]
        print(f"Seeded {count} tactical puzzles.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
