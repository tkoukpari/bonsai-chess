open! Core

type t = R | N | B | Q | K

let to_string = function R -> "R" | N -> "N" | B -> "B" | Q -> "Q" | K -> "K"

let of_char c =
  match Char.lowercase c with
  | 'k' -> Ok K
  | 'q' -> Ok Q
  | 'r' -> Ok R
  | 'b' -> Ok B
  | 'n' -> Ok N
  | c -> Or_error.errorf "invalid piece: %c" c
