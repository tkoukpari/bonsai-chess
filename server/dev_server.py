#!/usr/bin/env python3
"""Lightweight dev server with a dummy puzzle. No database required.

Usage:
    python dev_server.py
    Open http://localhost:8080/daily
"""

import os

from flask import Flask, abort, jsonify, make_response, request, send_from_directory
from puzzle_validation import parse_expected_moves, validate_solution

app = Flask(__name__)

PUZZLES = [
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
]
_puzzle_index = 0


def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return response


@app.route("/api/puzzle/daily", methods=["GET", "OPTIONS"])
def get_puzzle_daily():
    if request.method == "OPTIONS":
        return add_cors_headers(make_response("", 200))
    global _puzzle_index
    puzzle = PUZZLES[_puzzle_index % len(PUZZLES)]
    move_count = len(parse_expected_moves(puzzle["expected_moves"]))
    return add_cors_headers(
        jsonify({
            "id": puzzle["id"],
            "fen": puzzle["fen"],
            "moveCount": move_count,
            "elo": puzzle["elo"],
        })
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

    global _puzzle_index
    puzzle = PUZZLES[_puzzle_index % len(PUZZLES)]
    correct, error, _ = validate_solution(
        puzzle["fen"], puzzle["expected_moves"], moves
    )
    payload = {"correct": correct}
    if error:
        payload["error"] = error
    if correct:
        _puzzle_index += 1
    return add_cors_headers(jsonify(payload)), 200


WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "web"))


@app.route("/")
def serve_root():
    abort(404)


@app.route("/daily")
def serve_daily():
    return send_from_directory(WEB_DIR, "index.html")


@app.route("/daily/<path:path>")
def serve_daily_assets(path):
    if path.startswith("api/"):
        abort(404)
    file_path = os.path.join(WEB_DIR, path)
    if os.path.isfile(file_path):
        return send_from_directory(WEB_DIR, path)
    return send_from_directory(WEB_DIR, "index.html")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"Dev server running at http://localhost:{port}/daily")
    app.run(host="0.0.0.0", port=port, debug=True)
