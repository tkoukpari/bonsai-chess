(** [Puzzle] is a puzzle in the database. *)

open! Core
open! Import

type t = { id : Id.t; fen : Fen.t; moves : Move.t list; elo : Elo.t }
val to_yojson : t -> Yojson.Safe.t
val random : db:Db.t -> (t option, Caqti_error.t) Lwt_result.t
val daily : db:Db.t -> (t option, Caqti_error.t) Lwt_result.t
val get : db:Db.t -> int -> (t option, Caqti_error.t) Lwt_result.t
