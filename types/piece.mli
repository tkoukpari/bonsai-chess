open! Core

type t = R | N | B | Q | K

val to_string : t -> string
val of_char : char -> t Or_error.t
