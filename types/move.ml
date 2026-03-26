open! Core
open Or_error.Let_syntax

module Standard = struct
  module Source = struct
    type t = None | Piece of Piece.t | Pawn_file of Square.Column.t

    let to_string = function
      | None -> ""
      | Piece p -> Piece.to_string p
      | Pawn_file c -> Square.Column.to_string c
  end

  module Source_disambiguation = struct
    type t = { row : int option; column : Square.Column.t option }

    let to_string { row; column } =
      Option.value_map column ~default:"" ~f:Square.Column.to_string
      ^ Option.value_map row ~default:"" ~f:Int.to_string
  end

  type t = {
    source : Source.t;
    source_disambiguation : Source_disambiguation.t;
    destination : Square.t;
    takes : bool;
    check : bool;
    checkmate : bool;
    promote : Piece.t option;
  }

  let to_string
      {
        source;
        source_disambiguation;
        destination;
        takes;
        check;
        checkmate;
        promote;
      } =
    let promote_suffix =
      match promote with Some p -> "=" ^ Piece.to_string p | None -> ""
    in
    let f pred v = if pred then v else "" in
    Source.to_string source
    ^ Source_disambiguation.to_string source_disambiguation
    ^ f takes "x"
    ^ Square.to_string destination
    ^ promote_suffix ^ f check "+" ^ f checkmate "#"
end

module Castles = struct
  type t = Kingside | Queenside

  let to_string = function Kingside -> "O-O" | Queenside -> "O-O-O"
end

module One = struct
  type white = [ `white ]
  type black = [ `black ]
  type any = [ white | black ]

  type _ t =
    | Standard : Standard.t -> [> any ] t
    | Castles : Castles.t -> [> any ] t
    | Pass : [> white ] t

  let to_string (type a) (one : a t) : string =
    match one with
    | Pass -> ".."
    | Castles c -> Castles.to_string c
    | Standard s -> Standard.to_string s
end

type t =
  | White of One.any One.t
  | Pair of { white : One.any One.t; black : One.black One.t }

let move_number_re = Re.Pcre.regexp "^[0-9]+\\.$"
let has_letter_re = Re.Pcre.regexp "[a-zA-Z]"
let castles_re = Re.Pcre.regexp "^(O-O|0-0|O-O-O|0-0-0)$"

let is_move_token s =
  String.equal s ".."
  || (not (Re.Pcre.pmatch ~rex:move_number_re s))
     && Re.Pcre.pmatch ~rex:has_letter_re s

let tokens_of_pgn pgn =
  let pgn = String.strip pgn in
  if String.is_empty pgn then []
  else
    String.split_on_chars pgn ~on:[ ' ' ]
    |> List.filter ~f:(fun s ->
        (not (String.is_empty s))
        && (not (String.equal s "..."))
        && is_move_token s)

let standard_re =
  Re.Pcre.regexp
    "^([KQRBN])?([a-h])?([1-8])?x?([a-h])([1-8])(=[qQrRbBnN])?\\+?#?$"

let pawn_promotion_capture_re =
  Re.Pcre.regexp "^([a-h])x([a-h])([1-8])(=)?([qQrRbBnN])(\\+|#)?$"

let pawn_promotion_push_re =
  Re.Pcre.regexp "^([a-h])([1-8])(=)?([qQrRbBnN])(\\+|#)?$"

let parse_standard san =
  let san = String.strip san in
  let check_of_suffix = function
    | Some "+" -> (true, false)
    | Some "#" -> (false, true)
    | Some _ | None -> (false, false)
  in
  (match Re.Pcre.exec ~rex:pawn_promotion_capture_re san with
    | exception _ -> (
        match Re.Pcre.exec ~rex:pawn_promotion_push_re san with
        | exception _ -> None
        | groups ->
            let g i = Option.try_with (fun () -> Re.Group.get groups i) in
            let dest_s = Option.value_exn (g 1) ^ Option.value_exn (g 2) in
            let promote_s = Option.value_exn (g 4) in
            let check, checkmate = check_of_suffix (g 5) in
            Some (dest_s, promote_s, false, None, check, checkmate))
    | groups ->
        let g i = Option.try_with (fun () -> Re.Group.get groups i) in
        let pawn_file = Option.value_exn (g 1) in
        let dest_s = Option.value_exn (g 2) ^ Option.value_exn (g 3) in
        let promote_s = Option.value_exn (g 5) in
        let check, checkmate = check_of_suffix (g 6) in
        Some (dest_s, promote_s, true, Some pawn_file.[0], check, checkmate))
  |> Option.bind
       ~f:(fun (dest_s, promote_s, takes, pawn_file_opt, check, checkmate) ->
         match Square.of_string dest_s with
         | Error _ -> None
         | Ok destination -> (
             match Piece.of_char promote_s.[0] with
             | Error _ -> None
             | Ok promote_piece ->
                 let source : Standard.Source.t =
                   match pawn_file_opt with
                   | None -> None
                   | Some c -> (
                       match Square.Column.of_char c with
                       | Ok col -> Pawn_file col
                       | Error _ -> None)
                 in
                 Some
                   Standard.
                     {
                       source;
                       source_disambiguation =
                         {
                           Standard.Source_disambiguation.row = None;
                           column = None;
                         };
                       destination;
                       takes;
                       check;
                       checkmate;
                       promote = Some promote_piece;
                     }))
  |> function
  | Some s -> Ok s
  | None -> (
      match Re.Pcre.exec ~rex:standard_re san with
      | exception _ -> Or_error.error_string "no destination square in move"
      | groups ->
          let g i = Option.try_with (fun () -> Re.Group.get groups i) in
          let%bind destination =
            Square.of_string (Option.value_exn (g 4) ^ Option.value_exn (g 5))
          in
          let%bind promote =
            match g 6 with
            | Some s -> Piece.of_char s.[1] |> Or_error.map ~f:Option.some
            | None -> Ok None
          in
          let piece =
            Option.bind (g 1) ~f:(fun s -> Piece.of_char s.[0] |> Result.ok)
          in
          let file =
            Option.bind (g 2) ~f:(fun s ->
                Square.Column.of_char s.[0] |> Result.ok)
          in
          let row =
            Option.bind (g 3) ~f:(fun s ->
                Option.try_with (fun () -> Int.of_string s))
          in
          let takes = String.is_substring san ~substring:"x" in
          let check = String.is_suffix san ~suffix:"+" in
          let checkmate = String.is_suffix san ~suffix:"#" in
          let source : Standard.Source.t =
            match (piece, file, takes) with
            | None, Some c, true -> Pawn_file c
            | Some p, _, _ -> Piece p
            | _ -> None
          in
          let source_disambiguation =
            {
              Standard.Source_disambiguation.row;
              column = (if Option.is_some piece then file else None);
            }
          in
          return
            Standard.
              {
                source;
                source_disambiguation;
                destination;
                takes;
                check;
                checkmate;
                promote;
              })

let parse_one san =
  let san = String.strip san in
  if String.is_empty san then Or_error.error_string "empty move"
  else if String.equal san ".." then Ok One.Pass
  else if Re.Pcre.pmatch ~rex:castles_re (String.uppercase san) then
    Ok
      (One.Castles
         (if
            String.is_prefix san ~prefix:"O-O-O"
            || String.is_prefix san ~prefix:"0-0-0"
          then Castles.Queenside
          else Castles.Kingside))
  else parse_standard san >>| fun s -> One.Standard s

let to_string t =
  match t with
  | Pair { white; black } -> One.to_string white ^ " " ^ One.to_string black
  | White one -> One.to_string one

let to_string_list m =
  match m with
  | Pair { white; black } -> [ One.to_string white; One.to_string black ]
  | White one -> [ One.to_string one ]

let flatten moves = List.concat_map moves ~f:to_string_list

let of_pgn pgn =
  let tokens = tokens_of_pgn pgn in
  let ones_result = Or_error.all (List.map tokens ~f:parse_one) in
  Or_error.map ones_result ~f:(fun ones ->
      let rec group acc = function
        | [] -> List.rev acc
        | [ one ] -> List.rev (White one :: acc)
        | white :: black :: rest ->
            let black' : One.black One.t = Obj.magic black in
            group (Pair { white; black = black' } :: acc) rest
      in
      group [] ones)
