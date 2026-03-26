open! Core

module Column : sig
  type t = A | B | C | D | E | F | G | H

  val to_string : t -> string
  val of_char : char -> t Or_error.t
end

type t = { column : Column.t; row : int }

val to_string : t -> string
val of_string : string -> t Or_error.t
