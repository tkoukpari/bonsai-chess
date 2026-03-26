open! Core

let start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

let%test_unit "create_exn" =
  let board = Cpp_chess.create_exn start_fen in
  [%test_eq: string] (Cpp_chess.fen board) start_fen

let%test_unit "push_san legal move" =
  let board = Cpp_chess.create_exn start_fen in
  let result =
    match Cpp_chess.push_san board "e4" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> "Error: " ^ Error.to_string_hum e
  in
  [%test_eq: string] result
    "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

let%test_unit "push_san illegal move" =
  let board = Cpp_chess.create_exn start_fen in
  let result =
    match Cpp_chess.push_san board "e5" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result "illegal"

let%test_unit "push_san" =
  let board = Cpp_chess.create_exn start_fen in
  let result =
    match Cpp_chess.push_san board "e4" with
    | Error e -> Error.to_string_hum e
    | Ok () -> (
        match Cpp_chess.push_san board "e5" with
        | Error e -> Error.to_string_hum e
        | Ok () -> Cpp_chess.fen board)
  in
  [%test_eq: string] result
    "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

let fen_white_promo_a8 = "7k/P7/8/8/8/8/8/7K w - - 0 1"

let%test_unit "push_san promotion a8=Q (equals)" =
  let board = Cpp_chess.create_exn fen_white_promo_a8 in
  let result =
    match Cpp_chess.push_san board "a8=Q" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result "7Q/8/8/8/8/8/8/7K b - - 0 1"

let%test_unit "push_san promotion a8Q (no equals)" =
  let board = Cpp_chess.create_exn fen_white_promo_a8 in
  let result =
    match Cpp_chess.push_san board "a8Q" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result "7Q/8/8/8/8/8/8/7K b - - 0 1"

let%test_unit "push_san promotion lowercase piece a8=q" =
  let board = Cpp_chess.create_exn fen_white_promo_a8 in
  let result =
    match Cpp_chess.push_san board "a8=q" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result "7Q/8/8/8/8/8/8/7K b - - 0 1"

let fen_black_promo_a1 = "8/8/8/8/8/p7/7K/7k b - - 0 1"

let%test_unit "push_san black promotion a1=Q" =
  let board = Cpp_chess.create_exn fen_black_promo_a1 in
  let result =
    match Cpp_chess.push_san board "a1=Q" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result "8/8/8/8/8/8/7K/q7 w - - 0 2"

let fen_white_cxpromo =
  "1nbqkbnr/1Ppppppp/8/p7/8/8/PPPPPPPP/RNBQKBNR w KQk - 0 1"

let%test_unit "push_san capture promotion axb8=Q" =
  let board = Cpp_chess.create_exn fen_white_cxpromo in
  let result =
    match Cpp_chess.push_san board "axb8=Q" with
    | Ok () -> Cpp_chess.fen board
    | Error e -> Error.to_string_hum e
  in
  [%test_eq: string] result
    "1nQqkbnr/2pppppp/8/p7/8/8/PPPPPPPP/RNBQKBNR b KQk - 0 1"
