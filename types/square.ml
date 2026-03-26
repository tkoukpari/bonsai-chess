open! Core
open Or_error.Let_syntax

module Column = struct
  type t = A | B | C | D | E | F | G | H

  let to_string = function
    | A -> "a"
    | B -> "b"
    | C -> "c"
    | D -> "d"
    | E -> "e"
    | F -> "f"
    | G -> "g"
    | H -> "h"

  let of_string s =
    match s with
    | "a" -> Ok A
    | "b" -> Ok B
    | "c" -> Ok C
    | "d" -> Ok D
    | "e" -> Ok E
    | "f" -> Ok F
    | "g" -> Ok G
    | "h" -> Ok H
    | _ -> Or_error.errorf "invalid column: %s" s

  let of_char c = of_string (String.of_char (Char.lowercase c))
end

type t = { column : Column.t; row : int }

let to_string { column; row } = Column.to_string column ^ Int.to_string row
let of_string_re = Re.Pcre.regexp "^([a-hA-H])([1-8])$"

let of_string s =
  match Option.try_with (fun () -> Re.Pcre.exec ~rex:of_string_re s) with
  | Some groups ->
      let col_str = Re.Group.get groups 1 in
      let row_str = Re.Group.get groups 2 in
      let%map column = Column.of_string col_str in
      { column; row = Int.of_string row_str }
  | None -> Or_error.error_string "invalid square: must match [a-h][1-8]"
