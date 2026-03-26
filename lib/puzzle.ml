open! Core
open! Import
open Ppx_yojson_conv_lib.Yojson_conv.Primitives
open Caqti_type.Std
open Caqti_request.Infix

type t = { id : Id.t; fen : Fen.t; moves : Move.t list; elo : Elo.t }

type response = {
  id : int;
  fen : string;
  move_count : int; [@key "moveCount"]
  elo : int;
}
[@@deriving yojson]

let to_response (p : t) =
  let half_moves = Move.flatten p.moves in
  {
    id = Id.to_int_exn p.id;
    fen = Fen.to_string p.fen;
    move_count = List.length half_moves;
    elo = Elo.to_int_exn p.elo;
  }

let to_yojson p = yojson_of_response (to_response p)
let ( let* ) = Lwt_result.bind

let of_row (id, fen, expected_moves, elo) =
  let moves = Or_error.ok_exn (Move.of_pgn expected_moves) in
  {
    id = Id.of_int_exn id;
    fen = Fen.of_string fen;
    moves;
    elo = Elo.of_int_exn elo;
  }

let random ~db =
  Db.with_conn db ~f:(fun (module C) ->
      let req =
        (unit ->? t4 int string string int)
          "SELECT id, fen, expected_moves, elo FROM puzzles ORDER BY RANDOM() \
           LIMIT 1"
      in
      let* res = C.find_opt req () in
      Lwt.return_ok (Option.map res ~f:of_row))

let get ~db id =
  Db.with_conn db ~f:(fun (module C) ->
      let req =
        (int ->? t4 int string string int)
          "SELECT id, fen, expected_moves, elo FROM puzzles WHERE id = $1"
      in
      let* res = C.find_opt req id in
      Lwt.return_ok (Option.map res ~f:of_row))

let count ~db =
  Db.with_conn db ~f:(fun (module C) ->
      C.find ((unit ->! int) "SELECT COUNT(*) FROM puzzles") ())

let daily ~db =
  let* total = count ~db in
  if total = 0 then Lwt.return_ok None
  else
    let today = Date.today ~zone:(Lazy.force Time_float_unix.Zone.local) in
    let index = Int.abs (Date.hash today) mod total in
    Db.with_conn db ~f:(fun (module C) ->
        let req =
          (int ->? t4 int string string int)
            "SELECT id, fen, expected_moves, elo FROM puzzles ORDER BY id \
             LIMIT 1 OFFSET $1"
        in
        let* res = C.find_opt req index in
        Lwt.return_ok (Option.map res ~f:of_row))
