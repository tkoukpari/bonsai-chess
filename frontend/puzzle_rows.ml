open Core

type t = { move_number : int; white : int option; black : int option }

let build ~fen ~move_count : t list =
  if move_count <= 0 then []
  else
    let parts = String.split fen ~on:' ' in
    let white_first =
      match List.nth parts 1 with Some "b" -> false | _ -> true
    in
    let start_move_num =
      match List.nth parts 5 with
      | Some s -> ( try Int.of_string s with _ -> 1)
      | None -> 1
    in
    let row_map : (int, t) Stdlib.Hashtbl.t =
      Stdlib.Hashtbl.create (max 17 (2 * move_count))
    in
    let move_number = ref start_move_num in
    let is_white = ref white_first in
    let input_index = ref 0 in
    for _ = 0 to move_count - 1 do
      if not (Stdlib.Hashtbl.mem row_map !move_number) then
        Stdlib.Hashtbl.replace row_map !move_number
          { move_number = !move_number; white = None; black = None };
      let row = Stdlib.Hashtbl.find row_map !move_number in
      let row =
        if !is_white then { row with white = Some !input_index }
        else { row with black = Some !input_index }
      in
      Stdlib.incr input_index;
      Stdlib.Hashtbl.replace row_map !move_number row;
      if !is_white then is_white := false
      else (
        is_white := true;
        Stdlib.incr move_number)
    done;
    let alist = ref [] in
    Stdlib.Hashtbl.iter (fun k v -> alist := (k, v) :: !alist) row_map;
    !alist
    |> List.sort ~compare:(fun (a, _) (b, _) -> Int.compare a b)
    |> List.map ~f:snd
