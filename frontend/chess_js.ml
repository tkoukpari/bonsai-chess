open Js_of_ocaml

let get_global name =
  Js.Unsafe.get (Js.Unsafe.pure_js_expr "window") (Js.string name)

let on_move_end : (unit -> unit) ref = ref (fun () -> ())
let set_on_move_end f = on_move_end := f

let chessboard_create (board_id : string) (fen : string) : Js.Unsafe.any =
  let chessboard = get_global "Chessboard" in
  let cb =
    Js.wrap_callback (fun _ ->
        !on_move_end ();
        Js._true)
  in
  let config =
    Js.Unsafe.obj
      [|
        ("position", Js.Unsafe.inject (Js.string fen));
        ("showNotation", Js.Unsafe.inject (Js.bool false));
        ( "pieceTheme",
          Js.Unsafe.inject (Js.string "/img/chesspieces/merida/{piece}.svg") );
        ("moveSpeed", Js.Unsafe.inject (Js.number_of_float 600.));
        ("snapbackSpeed", Js.Unsafe.inject (Js.number_of_float 600.));
        ("snapSpeed", Js.Unsafe.inject (Js.number_of_float 100.));
        ("trashSpeed", Js.Unsafe.inject (Js.number_of_float 200.));
        ("appearSpeed", Js.Unsafe.inject (Js.number_of_float 200.));
        ("onMoveEnd", Js.Unsafe.inject cb);
      |]
  in
  Js.Unsafe.fun_call chessboard
    [|
      Js.Unsafe.inject (Js.string board_id);
      Js.Unsafe.inject config;
    |]

let chessboard_position (board : Js.Unsafe.any) (fen : string) (animate : bool)
    =
  ignore
    (Js.Unsafe.meth_call (Js.Unsafe.inject board) "position"
       [|
         Js.Unsafe.inject (Js.string fen); Js.Unsafe.inject (Js.bool animate);
       |])

let chessboard_move (board : Js.Unsafe.any) (move : string) =
  ignore
    (Js.Unsafe.meth_call (Js.Unsafe.inject board) "move"
       [| Js.Unsafe.inject (Js.string move) |])

let chessboard_resize (board : Js.Unsafe.any) =
  ignore (Js.Unsafe.meth_call (Js.Unsafe.inject board) "resize" [||])

let chess_create (fen : string) =
  let chess_global = get_global "Chess" in
  let ctor =
    try Js.Unsafe.get chess_global (Js.string "Chess") with _ -> chess_global
  in
  try
    Js.Unsafe.new_obj (Js.Unsafe.inject ctor)
      [| Js.Unsafe.inject (Js.string fen) |]
  with _ ->
    Js.Unsafe.fun_call (Js.Unsafe.inject ctor)
      [| Js.Unsafe.inject (Js.string fen) |]

let chess_move (game : Js.Unsafe.any) (san : string) : (string * string) option
    =
  let result =
    Js.Unsafe.meth_call (Js.Unsafe.inject game) "move"
      [| Js.Unsafe.inject (Js.string san) |]
  in
  if Js.typeof result = Js.string "object" then
    try
      let r = Js.Unsafe.coerce result in
      let from = Js.to_string (Js.Unsafe.get r (Js.string "from")) in
      let to_ = Js.to_string (Js.Unsafe.get r (Js.string "to")) in
      Some (from, to_)
    with _ -> None
  else None
