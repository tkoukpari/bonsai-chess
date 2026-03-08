"""
Server-side puzzle solution validation.

process_user_moves() is the hook for custom Python processing on user inputs
before validation. Override it to normalize, canonicalize, or transform moves.
"""

import chess


def parse_expected_moves(pgn: str) -> list[str]:
    """Extract flat list of SAN moves from PGN string (e.g. "34. Qxf7+ 34. ... Kg8 35. Bg5#")."""
    if not pgn or not pgn.strip():
        return []
    tokens = pgn.strip().split()
    moves = []
    for t in tokens:
        if t in ("..", "...") or (t.endswith(".") and t[:-1].isdigit()):
            continue
        if any(c.isalpha() for c in t):
            moves.append(t)
    return moves


def _normalize_piece_letter(san: str) -> str:
    """Capitalize piece letter if user typed lowercase (nf3 -> Nf3, kxd4 -> Kxd4).
    Do NOT capitalize 'b' - it could be Bishop (Bxa5) or the b-file for a pawn capture (bxa5)."""
    if not san or san[0] not in "kqrn":
        return san
    return san[0].upper() + san[1:]


def process_user_moves(moves: list[str]) -> list[str]:
    """
    Process user move inputs before validation.

    Override this function to add your own logic (e.g. normalize notation,
    strip suffixes, accept alternatives). Default: trim whitespace and
    accept lowercase piece letters (nf3, kxd4, etc.).
    """
    return [_normalize_piece_letter(m.strip()) for m in moves if m.strip()]


def validate_solution(fen: str, expected_pgn: str, user_moves: list[str]) -> tuple[bool, str | None, bool]:
    """
    Validate user moves against the expected solution.

    Returns (correct, error_message, elo_countable).
    - correct: True when solution is fully correct.
    - error_message: None when correct, else a user-facing message.
    - elo_countable: True only when user submitted valid SAN (parsable, legal moves).
      ELO is updated only when elo_countable; invalid syntax/moves do not affect rating.
    """
    expected = parse_expected_moves(expected_pgn)
    processed = process_user_moves(user_moves)

    if len(processed) != len(expected):
        return (
            False,
            f"Wrong number of moves. Expected {len(expected)}, got {len(processed)}.",
            False,
        )

    try:
        board = chess.Board(fen)
    except (ValueError, AssertionError):
        return False, "Invalid puzzle position.", False

    for i, (user_san, expected_san) in enumerate(zip(processed, expected)):
        try:
            user_move = board.parse_san(user_san)
        except chess.InvalidMoveError:
            return False, f"Invalid syntax at move {i + 1}: \"{user_san}\"", False
        except chess.IllegalMoveError:
            return False, f"Invalid move at move {i + 1}: \"{user_san}\"", False
        except chess.AmbiguousMoveError:
            return False, f"Ambiguous move at move {i + 1}: \"{user_san}\"", False

        try:
            expected_move = board.parse_san(expected_san)
        except (chess.InvalidMoveError, chess.AmbiguousMoveError):
            return False, "Puzzle data error: invalid expected move.", False

        if user_move != expected_move:
            return False, "Incorrect. Try again.", True

        if user_move not in board.legal_moves:
            return False, f"Invalid move at move {i + 1}: \"{user_san}\"", False

        board.push(user_move)

    return True, None, True
