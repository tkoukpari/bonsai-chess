open! Core

type t

external board_create : string -> t option = "caml_chess_board_create"
external board_push_uci : t -> string -> unit = "caml_chess_board_push_uci"

external board_parse_san : t -> string -> (string, string) result
  = "caml_chess_board_parse_san"

external board_fen : t -> string = "caml_chess_board_fen"

let fen t = board_fen t
let create_exn fen = Option.value_exn (board_create fen)

let push_san t san =
  match board_parse_san t san with
  | Ok uci ->
      board_push_uci t uci;
      Ok ()
  | Error msg -> Error (Error.of_string msg)
