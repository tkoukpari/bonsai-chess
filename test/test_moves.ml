open! Core

let test_pgn pgn =
  match Bonsai_chess_types.Move.of_pgn pgn with
  | Ok moves ->
      moves
      |> List.mapi ~f:(fun i m ->
          Printf.sprintf "%d. %s" (i + 1) (Bonsai_chess_types.Move.to_string m))
      |> String.concat ~sep:"\n"
  | Error e -> Error.to_string_hum e

let%test_unit "basic pawn moves" =
  [%test_eq: string] (test_pgn "1. e4 e5 2. Nf3 Nc6") "1. e4 e5\n2. Nf3 Nc6"

let%test_unit "empty pgn" = [%test_eq: string] (test_pgn "") ""

let%test_unit "single white move" =
  [%test_eq: string] (test_pgn "1. e4") "1. e4"

let%test_unit "pass then move (black starts)" =
  [%test_eq: string] (test_pgn "1. .. e5") "1. .. e5"

let%test_unit "kingside castling" =
  [%test_eq: string] (test_pgn "1. O-O") "1. O-O"

let%test_unit "queenside castling" =
  [%test_eq: string] (test_pgn "1. O-O-O") "1. O-O-O"

let%test_unit "captures" =
  [%test_eq: string] (test_pgn "1. exd5 Qxd5") "1. exd5 Qxd5"

let%test_unit "check" = [%test_eq: string] (test_pgn "1. Qxf7+") "1. Qxf7+"
let%test_unit "checkmate" = [%test_eq: string] (test_pgn "1. Qxf7#") "1. Qxf7#"
let%test_unit "promotion" = [%test_eq: string] (test_pgn "1. a8=Q") "1. a8=Q"

let%test_unit "promotion with checkmate" =
  [%test_eq: string] (test_pgn "1. d8=Q#") "1. d8=Q#"

let%test_unit "source disambiguation" =
  [%test_eq: string] (test_pgn "1. Nbd2 Nfd7 2. R1a3") "1. Nbd2 Nfd7\n2. R1a3"

let%test_unit "error: no destination square" =
  [%test_eq: string] (test_pgn "1. e4 z9") "no destination square in move"

let%test_unit "error: invalid square rank" =
  [%test_eq: string] (test_pgn "1. a9") "no destination square in move"

let%test_unit "error: invalid square file" =
  [%test_eq: string] (test_pgn "1. i1") "no destination square in move"

let%test_unit "error: invalid square row zero" =
  [%test_eq: string] (test_pgn "1. a0") "no destination square in move"

let%test_unit "error: invalid in second move" =
  [%test_eq: string]
    (test_pgn "1. e4 e5 2. Nf3 zzz")
    "no destination square in move"

let%test_unit "error: gibberish move" =
  [%test_eq: string] (test_pgn "1. xyz") "no destination square in move"

let%test_unit "error: only move number" = [%test_eq: string] (test_pgn "1.") ""

let%test_unit "error: out of range column" =
  [%test_eq: string] (test_pgn "1. k5") "no destination square in move"
