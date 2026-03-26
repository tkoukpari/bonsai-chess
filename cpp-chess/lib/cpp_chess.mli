open! Core

type t

val create_exn : string -> t
val push_san : t -> string -> unit Or_error.t
val fen : t -> string
