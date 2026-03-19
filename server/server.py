#!/usr/bin/env python3

import argparse
import hashlib
import math
import os
import random
from contextlib import contextmanager
from datetime import date
from functools import wraps

from flask import Flask, abort, jsonify, make_response, request, send_from_directory

from puzzle_validation import parse_expected_moves, validate_solution

DEV_MODE = False

DEV_PUZZLES = [
    {
        "id": 1,
        "fen": "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
        "expected_moves": "1. Qxf7#",
        "elo": 800,
    },
    {
        "id": 2,
        "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        "expected_moves": "1... e5",
        "elo": 400,
    },
    {
        "id": 3,
        "fen": "r1bqkbnr/pppppppp/2n5/8/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 2",
        "expected_moves": "1... e5",
        "elo": 500,
    },
    {
        "id": 4,
        "fen": "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
        "expected_moves": "1... e6",
        "elo": 600,
    },
]
_dev_current_puzzle = None

default_elo_rating = 1200
elo_rating_change_factor = 32
jwt_secret = os.environ.get("JWT_SECRET", "dev-secret-change-in-production")
jwt_algorithm = "HS256"

app = Flask(__name__)


def _init_db_deps():
    """Import DB dependencies lazily so --dev works without them installed."""
    global psycopg2, RealDictCursor, bcrypt, jwt, DATABASE_URL
    import psycopg2 as _pg
    from psycopg2.extras import RealDictCursor as _rdc
    import bcrypt as _bc
    import jwt as _jwt
    psycopg2 = _pg
    RealDictCursor = _rdc
    bcrypt = _bc
    jwt = _jwt
    DATABASE_URL = os.environ["DATABASE_URL"]


def _cursor(conn):
    return conn.cursor(cursor_factory=RealDictCursor)


@contextmanager
def get_database_connection():
    conn = psycopg2.connect(DATABASE_URL)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def initialize_database():
    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS puzzles (
                id SERIAL PRIMARY KEY,
                fen TEXT NOT NULL,
                expected_moves TEXT NOT NULL,
                elo INTEGER NOT NULL DEFAULT 1200
            )
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL UNIQUE,
                email TEXT NOT NULL,
                password_hash BYTEA,
                elo INTEGER NOT NULL DEFAULT 1200,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS user_puzzle_attempts (
                user_id INTEGER NOT NULL REFERENCES users(id),
                puzzle_id INTEGER NOT NULL REFERENCES puzzles(id),
                correct INTEGER NOT NULL,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (user_id, puzzle_id)
            )
            """
        )
        cursor.execute("SELECT COUNT(*) as c FROM puzzles")
        if cursor.fetchone()["c"] == 0:
            cursor.execute(
                "INSERT INTO puzzles (fen, expected_moves, elo) VALUES (%s, %s, %s)",
                (
                    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                    "1. e4 e5 2. Nf3 Nc6",
                    1200,
                ),
            )


def _dev_pick_puzzle():
    global _dev_current_puzzle
    _dev_current_puzzle = random.choice(DEV_PUZZLES)
    return _dev_current_puzzle


def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return response


def get_current_user_id_from_token():
    if DEV_MODE:
        return None
    authorization = request.headers.get("Authorization")
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token_string = authorization[7:]
    try:
        payload = jwt.decode(token_string, jwt_secret, algorithms=[jwt_algorithm])
        return payload.get("user_id")
    except jwt.InvalidTokenError:
        return None


def require_authentication(route_handler):
    @wraps(route_handler)
    def decorated_handler(*args, **kwargs):
        user_id = get_current_user_id_from_token()
        if user_id is None:
            return jsonify({"error": "authentication required"}), 401
        return route_handler(user_id, *args, **kwargs)

    return decorated_handler


def compute_elo_change(player_elo, opponent_elo, player_won):
    expected_score = 1.0 / (1.0 + math.pow(10, (opponent_elo - player_elo) / 400))
    actual_score = 1.0 if player_won else 0.0
    return round(elo_rating_change_factor * (actual_score - expected_score))


def is_valid_email_address(email_address):
    trimmed = email_address.strip()
    if not trimmed or "@" not in trimmed:
        return False
    local_part, _, domain_part = trimmed.partition("@")
    return len(local_part) >= 1 and len(domain_part) >= 3 and "." in domain_part




@app.route("/api/auth/login", methods=["POST", "OPTIONS"])
def login():
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))
    body = request.get_json()
    if not body or "username" not in body or "password" not in body:
        return jsonify({"error": "username and password required"}), 400
    username = body["username"].strip()
    password = body["password"]
    if not username:
        return jsonify({"error": "username required"}), 400
    if not isinstance(password, str):
        return jsonify({"error": "invalid password"}), 400

    ph = "%s"
    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute(
            f"SELECT id, username, email, elo, password_hash FROM users WHERE username = {ph}",
            (username,),
        )
        user_row = cursor.fetchone()
    if user_row is None:
        return jsonify({"error": "invalid username or password"}), 401
    stored_password_hash = user_row["password_hash"]
    if isinstance(stored_password_hash, memoryview):
        stored_password_hash = bytes(stored_password_hash)
    if not stored_password_hash or not bcrypt.checkpw(password.encode("utf-8"), stored_password_hash):
        return jsonify({"error": "invalid username or password"}), 401

    token = jwt.encode(
        {"user_id": user_row["id"]},
        jwt_secret,
        algorithm=jwt_algorithm,
    )
    if hasattr(token, "decode"):
        token = token.decode("ascii")
    return add_cors_headers(
        jsonify(
            {
                "token": token,
                "user": {
                    "id": user_row["id"],
                    "username": user_row["username"],
                    "email": user_row["email"],
                    "elo": user_row["elo"],
                },
            }
        )
    )


@app.route("/api/users", methods=["POST", "OPTIONS"])
def create_user():
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))
    body = request.get_json()
    if not body or "username" not in body or "email" not in body or "password" not in body:
        return jsonify({"error": "username, email, and password required"}), 400
    username = body["username"].strip()
    email = body["email"].strip()
    password = body["password"]
    if not username or not email:
        return jsonify({"error": "username and email required"}), 400
    if not isinstance(password, str) or len(password) < 8:
        return jsonify({"error": "password must be at least 8 characters"}), 400
    if not is_valid_email_address(email):
        return jsonify({"error": "please enter a valid email address"}), 400

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())

    ph = "%s"
    try:
        with get_database_connection() as connection:
            cursor = _cursor(connection)
            cursor.execute(
                f"INSERT INTO users (username, email, password_hash, elo) VALUES ({ph}, {ph}, {ph}, {ph}) RETURNING id, username, email, elo",
                (username, email, password_hash, default_elo_rating),
            )
            user_row = cursor.fetchone()
        if user_row:
            token = jwt.encode(
                {"user_id": user_row["id"]},
                jwt_secret,
                algorithm=jwt_algorithm,
            )
            if hasattr(token, "decode"):
                token = token.decode("ascii")
            return add_cors_headers(
                jsonify(
                    {
                        "token": token,
                        "user": {
                            "id": user_row["id"],
                            "username": user_row["username"],
                            "email": user_row["email"],
                            "elo": user_row["elo"],
                        },
                    }
                )
            ), 201
    except psycopg2.IntegrityError:
        return jsonify({"error": "username already taken"}), 409
    return jsonify({"error": "failed to create user"}), 500


@app.route("/api/users/me", methods=["GET", "DELETE", "OPTIONS"])
@require_authentication
def get_or_delete_current_user(user_id):
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))
    ph = "%s"
    if request.method == "DELETE":
        with get_database_connection() as connection:
            cursor = _cursor(connection)
            cursor.execute(f"DELETE FROM user_puzzle_attempts WHERE user_id = {ph}", (user_id,))
            cursor.execute(f"DELETE FROM users WHERE id = {ph} RETURNING id", (user_id,))
            if cursor.rowcount == 0:
                return jsonify({"error": "user not found"}), 404
        return add_cors_headers(make_response("", 204))

    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute(
            f"SELECT id, username, email, elo FROM users WHERE id = {ph}",
            (user_id,),
        )
        user_row = cursor.fetchone()
    if user_row is None:
        return jsonify({"error": "user not found"}), 404
    return add_cors_headers(
        jsonify({"id": user_row["id"], "username": user_row["username"], "email": user_row["email"], "elo": user_row["elo"]})
    )


@app.route("/api/puzzle", methods=["GET", "OPTIONS"])
def get_puzzle():
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))

    if DEV_MODE:
        puzzle = _dev_pick_puzzle()
        move_count = len(parse_expected_moves(puzzle["expected_moves"]))
        return add_cors_headers(jsonify({
            "id": puzzle["id"], "fen": puzzle["fen"],
            "moveCount": move_count, "elo": puzzle["elo"],
        }))

    user_id = get_current_user_id_from_token()
    elo_range = request.args.get("elo_range", 100, type=int)
    ph = "%s"

    with get_database_connection() as connection:
        cursor = _cursor(connection)
        if user_id:
            cursor.execute(f"SELECT elo FROM users WHERE id = {ph}", (user_id,))
            user_row = cursor.fetchone()
            user_elo = user_row["elo"] if user_row else default_elo_rating
            cursor.execute(
                f"""
                SELECT p.id, p.fen, p.expected_moves, p.elo
                FROM puzzles p
                LEFT JOIN user_puzzle_attempts u ON p.id = u.puzzle_id AND u.user_id = {ph}
                WHERE u.puzzle_id IS NULL
                  AND p.elo BETWEEN {ph} AND {ph}
                ORDER BY RANDOM() LIMIT 1
                """,
                (user_id, user_elo - elo_range, user_elo + elo_range),
            )
            puzzle_row = cursor.fetchone()
            if puzzle_row is None:
                cursor.execute(
                    f"""
                    SELECT p.id, p.fen, p.expected_moves, p.elo
                    FROM puzzles p
                    LEFT JOIN user_puzzle_attempts u ON p.id = u.puzzle_id AND u.user_id = {ph}
                    WHERE u.puzzle_id IS NULL
                    ORDER BY RANDOM() LIMIT 1
                    """,
                    (user_id,),
                )
                puzzle_row = cursor.fetchone()
        else:
            cursor.execute(
                "SELECT id, fen, expected_moves, elo FROM puzzles ORDER BY RANDOM() LIMIT 1"
            )
            puzzle_row = cursor.fetchone()

    if puzzle_row is None:
        return make_response("No puzzles available (or all done)", 500)
    move_count = len(parse_expected_moves(puzzle_row["expected_moves"]))
    return add_cors_headers(
        jsonify(
            {
                "id": puzzle_row["id"],
                "fen": puzzle_row["fen"],
                "moveCount": move_count,
                "elo": puzzle_row["elo"],
            }
        )
    )


def _daily_puzzle_index(total_count: int) -> int:
    """Deterministic index from today's date (UTC). Same day = same puzzle."""
    today = date.today()
    day_str = today.isoformat()
    h = hashlib.sha256(day_str.encode()).hexdigest()
    return int(h[:16], 16) % total_count if total_count else 0


@app.route("/api/puzzle/daily", methods=["GET", "OPTIONS"])
def get_puzzle_daily():
    """Return the puzzle of the day: hash(date) % count, then index into puzzles by id."""
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))

    if DEV_MODE:
        n = len(DEV_PUZZLES)
        idx = _daily_puzzle_index(n)
        puzzle = DEV_PUZZLES[idx]
        move_count = len(parse_expected_moves(puzzle["expected_moves"]))
        return add_cors_headers(jsonify({
            "id": puzzle["id"], "fen": puzzle["fen"],
            "moveCount": move_count, "elo": puzzle["elo"],
        }))

    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute("SELECT COUNT(*) AS c FROM puzzles")
        total = cursor.fetchone()["c"]
    if total == 0:
        return make_response("No puzzles available", 500)
    idx = _daily_puzzle_index(total)
    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute(
            "SELECT id, fen, expected_moves, elo FROM puzzles ORDER BY id LIMIT 1 OFFSET %s",
            (idx,),
        )
        puzzle_row = cursor.fetchone()
    if puzzle_row is None:
        return make_response("No puzzles available", 500)
    move_count = len(parse_expected_moves(puzzle_row["expected_moves"]))
    return add_cors_headers(
        jsonify(
            {
                "id": puzzle_row["id"],
                "fen": puzzle_row["fen"],
                "moveCount": move_count,
                "elo": puzzle_row["elo"],
            }
        )
    )


@app.route("/api/puzzle/result", methods=["POST", "OPTIONS"])
def submit_puzzle_result():
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))
    body = request.get_json()
    if not body:
        return jsonify({"error": "JSON body required"}), 400
    moves = body.get("moves")
    if not isinstance(moves, list) or not all(isinstance(m, str) for m in moves):
        return jsonify({"error": "moves must be a list of strings"}), 400

    if DEV_MODE:
        puzzle = _dev_current_puzzle or _dev_pick_puzzle()
        correct, error, _ = validate_solution(
            puzzle["fen"], puzzle["expected_moves"], moves
        )
        payload = {"correct": correct}
        if error:
            payload["error"] = error
        if correct:
            _dev_pick_puzzle()
        return add_cors_headers(jsonify(payload)), 200

    puzzle_id = body.get("puzzle_id")
    if puzzle_id is None:
        return jsonify({"error": "puzzle_id required"}), 400

    ph = "%s"
    with get_database_connection() as connection:
        cursor = _cursor(connection)
        cursor.execute(
            f"SELECT fen, expected_moves, elo FROM puzzles WHERE id = {ph}", (puzzle_id,)
        )
        puzzle_row = cursor.fetchone()
    if puzzle_row is None:
        return jsonify({"error": "puzzle not found"}), 404

    correct, error, elo_countable = validate_solution(
        puzzle_row["fen"], puzzle_row["expected_moves"], moves
    )
    payload = {"correct": correct}
    if error:
        payload["error"] = error

    user_id = get_current_user_id_from_token()
    if user_id and elo_countable:
        try:
            with get_database_connection() as connection:
                cursor = _cursor(connection)
                cursor.execute(
                    f"SELECT correct FROM user_puzzle_attempts WHERE user_id = {ph} AND puzzle_id = {ph}",
                    (user_id, puzzle_id),
                )
                attempt_row = cursor.fetchone()
                if attempt_row is None:
                    cursor.execute(f"SELECT elo FROM users WHERE id = {ph}", (user_id,))
                    user_row = cursor.fetchone()
                    puzzle_elo = puzzle_row["elo"]
                    if not user_row:
                        return jsonify({"error": "user not found"}), 404
                    user_elo = user_row["elo"]
                    elo_delta = compute_elo_change(user_elo, puzzle_elo, correct)
                    new_elo = max(100, user_elo + elo_delta)

                    cursor.execute(
                        f"INSERT INTO user_puzzle_attempts (user_id, puzzle_id, correct) VALUES ({ph}, {ph}, {ph})",
                        (user_id, puzzle_id, 1 if correct else 0),
                    )
                    cursor.execute(f"UPDATE users SET elo = {ph} WHERE id = {ph}", (new_elo, user_id))
                    cursor.execute(f"SELECT elo FROM users WHERE id = {ph}", (user_id,))
                    updated_row = cursor.fetchone()
                    payload["elo"] = updated_row["elo"]
                    payload["eloChange"] = elo_delta
        except psycopg2.IntegrityError:
            return jsonify({"error": "invalid puzzle_id"}), 400

    return add_cors_headers(jsonify(payload)), 200


@app.route("/api/<path:subpath>", methods=["OPTIONS"])
def cors_preflight(subpath):
    return add_cors_headers(make_response("", 200))


WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "web"))


@app.route("/")
def serve_root():
    return send_from_directory(WEB_DIR, "index.html")


@app.route("/daily")
def serve_daily():
    return send_from_directory(WEB_DIR, "daily.html")


def _static_response(path, directory=WEB_DIR):
    resp = send_from_directory(directory, path)
    if path.startswith("img/") or path.endswith(".css") or path.endswith(".js"):
        resp.headers["Cache-Control"] = "public, max-age=31536000"
    return resp


@app.route("/daily/<path:path>")
def serve_daily_assets(path):
    if path.startswith("api/"):
        abort(404)
    file_path = os.path.join(WEB_DIR, path)
    if os.path.isfile(file_path):
        return _static_response(path)
    return send_from_directory(WEB_DIR, "daily.html")


@app.route("/notation")
def serve_notation():
    return send_from_directory(WEB_DIR, "notation.html")


@app.route("/<path:path>")
def serve_static(path):
    if path.startswith("api") or path in ("daily", "notation"):
        abort(404)
    if path in ("", "index.html"):
        return send_from_directory(WEB_DIR, "index.html")
    file_path = os.path.join(WEB_DIR, path)
    if os.path.isfile(file_path):
        return _static_response(path)
    abort(404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", action="store_true",
                        help="Run with dummy puzzles, no database required")
    args = parser.parse_args()

    port = int(os.environ.get("PORT", 8080))

    if args.dev:
        DEV_MODE = True
        print(f"Dev server (no database) running at http://localhost:{port}/daily")
        app.run(host="0.0.0.0", port=port, debug=True)
    else:
        _init_db_deps()
        initialize_database()
        app.run(host="0.0.0.0", port=port)
else:
    _init_db_deps()
    initialize_database()
