open! Core
open! Async_kernel
open! Bonsai_web
open Bonsai.Let_syntax
open Js_of_ocaml
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type puzzle_response = {
  id : int;
  fen : string;
  move_count : int; [@key "moveCount"]
  elo : int;
}
[@@deriving of_yojson]

type result_response = { correct : bool; error : string option [@default None] }
[@@deriving of_yojson]

type puzzle_ui = {
  puzzle : puzzle_response;
  inputs : string array;
  check_locked : bool;
  is_animating : bool;
  awaiting_next : bool;
  feedback : string;
  feedback_ok : bool;
}

type model = Loading | Error of string | Puzzle of puzzle_ui

let board_ref : Js.Unsafe.any option ref = ref None
let resize_listener_installed : bool ref = ref false
let current_model : model ref = ref Loading

let auto_advance_after_solve puzzle_api =
  String.is_suffix puzzle_api ~suffix:"/daily"

let puzzle_api_for_page = function
  | I18n.Daily -> "/api/puzzle/daily"
  | I18n.Home | I18n.Notation -> "/api/puzzle"

let to_play_label ~lang fen =
  let parts = String.split fen ~on:' ' in
  match List.nth parts 1 with
  | Some "b" -> I18n.to_play_black lang
  | _ -> I18n.to_play_white lang

let set_document_lang_dir lang =
  let open Js_of_ocaml in
  let el = Dom_html.document##.documentElement in
  let set_attr name v =
    ignore
      (Js.Unsafe.meth_call (Js.Unsafe.inject el) "setAttribute"
         [| Js.Unsafe.inject (Js.string name); Js.Unsafe.inject (Js.string v) |])
  in
  set_attr "dir" I18n.layout_dir;
  set_attr "lang" (I18n.html_lang lang)

let txt ~lang str =
  match (lang : I18n.lang) with
  | Fa ->
      Vdom.Node.span
        ~attrs:
          [
            Vdom.Attr.class_ "i18n-fa";
            Vdom.Attr.create "dir" "rtl";
            Vdom.Attr.create "lang" "fa";
          ]
        [ Vdom.Node.text str ]
  | En -> Vdom.Node.text str

let set_model_var model_var m =
  (match m with Error _ -> board_ref := None | _ -> ());
  current_model := m;
  Bonsai.Var.set model_var m

let after_next_paint (f : unit -> unit) =
  ignore
    (Dom_html.window##requestAnimationFrame
       (Js.wrap_callback (fun _ ->
            ignore
              (Dom_html.window##requestAnimationFrame
                 (Js.wrap_callback (fun _ -> f ()))))))

let install_resize_listener () =
  if not !resize_listener_installed then (
    resize_listener_installed := true;
    ignore
      (Dom_html.addEventListener Dom_html.window Dom_html.Event.resize
         (Dom_html.handler (fun _ ->
              (match !board_ref with
              | Some b -> Chess_js.chessboard_resize b
              | None -> ());
              Js._true))
         Js._false))

let sync_board ~fen ~animate =
  after_next_paint (fun () ->
      match !board_ref with
      | None ->
          let b = Chess_js.chessboard_create "board" fen in
          board_ref := Some b;
          install_resize_listener ();
          Chess_js.chessboard_resize b
      | Some b ->
          Chess_js.chessboard_position b fen animate;
          if not animate then Chess_js.chessboard_resize b)

let fetch_puzzle ~lang ~puzzle_api model_var =
  Effect.of_deferred_fun (fun () ->
      set_model_var model_var Loading;
      Deferred.map (Http.get puzzle_api) ~f:(function
        | Error e -> set_model_var model_var (Error e)
        | Ok body -> (
            match puzzle_response_of_yojson (Yojson.Safe.from_string body) with
            | exception _ ->
                set_model_var model_var (Error (I18n.invalid_response lang))
            | p ->
                let _ = p.elo in
                set_model_var model_var
                  (Puzzle
                     {
                       puzzle = p;
                       inputs = Array.create ~len:p.move_count "";
                       check_locked = false;
                       is_animating = false;
                       awaiting_next = false;
                       feedback = "";
                       feedback_ok = false;
                     });
                sync_board ~fen:p.fen ~animate:false)))

let post_moves ~(puzzle_id : int) (moves : string list) =
  let body =
    Yojson.Safe.to_string
      (`Assoc
         [
           ("puzzle_id", `Int puzzle_id);
           ("moves", `List (List.map moves ~f:(fun s -> `String s)));
         ])
  in
  Http.post "/api/puzzle/result" body

let trimmed_move_list (inputs : string array) =
  Array.to_list inputs |> List.map ~f:String.strip
  |> List.filter ~f:(fun s -> not (String.is_empty s))

let rec animate_solution_steps (board : Js.Unsafe.any) (game : Js.Unsafe.any)
    (sans : string array) (idx : int) ~finished : unit Deferred.t =
  if idx >= Array.length sans then (
    Clock_ns.after (Time_ns.Span.of_ms 1500.) >>= fun () ->
    finished ();
    Deferred.return ())
  else
    let san = sans.(idx) in
    match Chess_js.chess_move game san with
    | None -> animate_solution_steps board game sans (idx + 1) ~finished
    | Some (from, to_) ->
        let ivar = Ivar.create () in
        let filled = ref false in
        Chess_js.set_on_move_end (fun () ->
            if not !filled then (
              filled := true;
              Ivar.fill_exn ivar ()));
        Chess_js.chessboard_move board (sprintf "%s-%s" from to_);
        Ivar.read ivar >>= fun () ->
        Clock_ns.after (Time_ns.Span.of_ms 250.) >>= fun () ->
        animate_solution_steps board game sans (idx + 1) ~finished

let run_solution_animation ~fen ~(sans : string array) ~on_complete =
  match !board_ref with
  | None -> on_complete ()
  | Some board ->
      Chess_js.chessboard_position board fen false;
      let game = Chess_js.chess_create fen in
      Deferred.don't_wait_for
        ( Clock_ns.after (Time_ns.Span.of_ms 500.) >>= fun () ->
          animate_solution_steps board game sans 0 ~finished:(fun () ->
              on_complete ()) )

let move_input_attrs ~model_var ~ui ~idx =
  let disabled_attrs =
    if ui.check_locked || ui.is_animating || ui.awaiting_next then
      [ Vdom.Attr.disabled ]
    else []
  in
  Vdom.Node.input
    ~attrs:
      ([
         Vdom.Attr.type_ "text";
         Vdom.Attr.class_ "move-input";
         Vdom.Attr.create "dir" "ltr";
         Vdom.Attr.create "autocomplete" "off";
         Vdom.Attr.value ui.inputs.(idx);
         Vdom.Attr.on_input (fun _ev v ->
             (match !current_model with
             | Puzzle u ->
                 let inputs = Array.copy u.inputs in
                 inputs.(idx) <- v;
                 set_model_var model_var (Puzzle { u with inputs })
             | _ -> ());
             Vdom.Effect.Ignore);
       ]
      @ disabled_attrs)
    ()

let move_placeholder_input =
  Vdom.Node.input
    ~attrs:
      [
        Vdom.Attr.type_ "text";
        Vdom.Attr.class_ "move-input";
        Vdom.Attr.disabled;
        Vdom.Attr.create "style" "visibility:hidden";
      ]
    ()

let move_rows ~model_var ~(ui : puzzle_ui) ~(p : puzzle_response) =
  let rows = Puzzle_rows.build ~fen:p.fen ~move_count:p.move_count in
  List.map rows ~f:(fun r ->
      let cell = function
        | None -> move_placeholder_input
        | Some idx -> move_input_attrs ~model_var ~ui ~idx
      in
      Vdom.Node.div
        ~attrs:[ Vdom.Attr.class_ "move-row" ]
        [
          Vdom.Node.span
            ~attrs:[ Vdom.Attr.class_ "move-num" ]
            [ Vdom.Node.text (sprintf "%d." r.move_number) ];
          cell r.white;
          cell r.black;
        ])
  |> Vdom.Node.div ~attrs:[ Vdom.Attr.create "style" "margin-bottom:0.75rem" ]

let load_next_puzzle ~lang ~puzzle_api model_var =
  Deferred.map (Http.get puzzle_api) ~f:(function
    | Error _ -> (
        match !current_model with
        | Puzzle u ->
            set_model_var model_var
              (Puzzle
                 {
                   u with
                   check_locked = false;
                   is_animating = false;
                   feedback = I18n.could_not_load_next lang;
                   feedback_ok = false;
                 })
        | _ -> ())
    | Ok body -> (
        match puzzle_response_of_yojson (Yojson.Safe.from_string body) with
        | exception _ ->
            set_model_var model_var (Error (I18n.invalid_response lang))
        | p ->
            let _ = p.elo in
            set_model_var model_var
              (Puzzle
                 {
                   puzzle = p;
                   inputs = Array.create ~len:p.move_count "";
                   check_locked = false;
                   is_animating = false;
                   awaiting_next = false;
                   feedback = "";
                   feedback_ok = false;
                 });
            sync_board ~fen:p.fen ~animate:true))

let handle_primary_button ~lang ~puzzle_api ~auto_advance model_var =
  Effect.of_deferred_fun (fun () ->
      match !current_model with
      | Puzzle ui when ui.awaiting_next ->
          load_next_puzzle ~lang ~puzzle_api model_var
      | Puzzle ui ->
          let moves = trimmed_move_list ui.inputs in
          if List.length moves <> ui.puzzle.move_count then (
            set_model_var model_var
              (Puzzle
                 {
                   ui with
                   feedback = I18n.enter_all_moves ui.puzzle.move_count lang;
                   feedback_ok = false;
                 });
            Deferred.return ())
          else (
            set_model_var model_var
              (Puzzle
                 {
                   ui with
                   check_locked = true;
                   feedback = "";
                   feedback_ok = false;
                 });
            Deferred.map (post_moves ~puzzle_id:ui.puzzle.id moves) ~f:(function
              | Error _ ->
                  set_model_var model_var
                    (Puzzle
                       {
                         ui with
                         check_locked = false;
                         feedback = I18n.cannot_reach_server lang;
                         feedback_ok = false;
                       })
              | Ok resp_body -> (
                  match
                    result_response_of_yojson (Yojson.Safe.from_string resp_body)
                  with
                  | exception _ ->
                      set_model_var model_var
                        (Puzzle
                           {
                             ui with
                             check_locked = false;
                             feedback = I18n.invalid_response lang;
                             feedback_ok = false;
                           })
                  | r when r.correct ->
                      let sans = Array.of_list moves in
                      set_model_var model_var
                        (Puzzle
                           {
                             ui with
                             feedback = I18n.correct_well_done lang;
                             feedback_ok = true;
                             is_animating = true;
                             check_locked = true;
                           });
                      run_solution_animation ~fen:ui.puzzle.fen ~sans
                        ~on_complete:(fun () ->
                          if auto_advance then
                            Deferred.don't_wait_for
                              (load_next_puzzle ~lang ~puzzle_api model_var)
                          else
                            match !current_model with
                            | Puzzle u ->
                                set_model_var model_var
                                  (Puzzle
                                     {
                                       u with
                                       awaiting_next = true;
                                       is_animating = false;
                                       check_locked = false;
                                     })
                            | _ -> ())
                  | r ->
                      set_model_var model_var
                        (Puzzle
                           {
                             ui with
                             check_locked = false;
                             feedback =
                               Option.value r.error
                                 ~default:(I18n.incorrect_try_again lang);
                             feedback_ok = false;
                           }))))
      | _ -> Deferred.return ())

let nav_row ~lang ~page =
  let links =
    Vdom.Node.div
      ~attrs:[ Vdom.Attr.class_ "nav-bar" ]
      [
        Vdom.Node.a
          ~attrs:
            [
              Vdom.Attr.href (I18n.href_puzzles lang);
              Vdom.Attr.class_ "nav-link";
            ]
          [ txt ~lang (I18n.nav_puzzles lang) ];
        Vdom.Node.a
          ~attrs:
            [
              Vdom.Attr.href (I18n.href_daily lang); Vdom.Attr.class_ "nav-link";
            ]
          [ txt ~lang (I18n.nav_daily lang) ];
        Vdom.Node.a
          ~attrs:
            [
              Vdom.Attr.href (I18n.href_notation lang);
              Vdom.Attr.class_ "nav-link";
            ]
          [ txt ~lang (I18n.nav_notation lang) ];
      ]
  in
  let toggle =
    Vdom.Node.a
      ~attrs:
        [
          Vdom.Attr.href (I18n.lang_switch_href ~current_lang:lang ~page);
          Vdom.Attr.class_ "nav-link lang-toggle";
        ]
      [ txt ~lang (I18n.lang_switch_label lang) ]
  in
  Vdom.Node.div
    ~attrs:
      [
        Vdom.Attr.class_
          "d-flex w-100 justify-content-between align-items-center mb-3 \
           flex-nowrap gap-2 nav-top-row";
      ]
    [ links; toggle ]

let notation_content ~lang =
  let mk line = Vdom.Node.p [ txt ~lang line ] in
  match (lang : I18n.lang) with
  | Fa ->
      Vdom.Node.div
        ~attrs:[ Vdom.Attr.id "notation-content"; Vdom.Attr.create "dir" "rtl" ]
        [
          mk "SAN (نماد جبری استاندارد)";
          mk "SAN روش نوشتن حرکات شطرنج است؛ هر حرکت یک رشته کوتاه است.";
          mk "پیاده ها: فقط خانه، مثل e4 یا exd5";
          mk "مهره ها: K=شاه، Q=وزیر، R=رخ، B=فیل، N=اسب. مثل Nf3";
          mk "زدن: x بین مهره یا ستون پیاده و خانه، مثل Nxe5 یا exd5";
          mk "قلعه: O-O یا O-O-O";
          mk "ترفیع: = و مهره جدید، مثل e8=Q";
          mk "کیش با + و کیش مات با # نشان داده می شود.";
        ]
  | En ->
      Vdom.Node.div
        ~attrs:[ Vdom.Attr.id "notation-content" ]
        [
          mk "SAN (Standard Algebraic Notation)";
          mk "SAN is a compact way to write chess moves.";
          mk "Pawns: just the square, e.g. e4 or exd5.";
          mk "Pieces: K=king, Q=queen, R=rook, B=bishop, N=knight, e.g. Nf3.";
          mk "Capture uses x, e.g. Nxe5 or exd5.";
          mk "Castling: O-O (kingside), O-O-O (queenside).";
          mk "Promotion adds = and the piece, e.g. e8=Q.";
          mk "Check uses + and checkmate uses #.";
        ]

let component ~lang ~page puzzle_api graph =
  let model_var = Bonsai.Var.create Loading in
  let model = Bonsai.Var.value model_var in
  let auto_advance = auto_advance_after_solve puzzle_api in
  let _ =
    Bonsai.Edge.lifecycle
      ~on_activate:
        (Bonsai.Value.return
           (Effect.of_sync_fun (fun () -> set_document_lang_dir lang) ()))
      () graph
  in
  let _ =
    match page with
    | I18n.Notation -> ()
    | I18n.Home | I18n.Daily ->
        Bonsai.Edge.lifecycle
          ~on_activate:
            (Bonsai.Value.return (fetch_puzzle ~lang ~puzzle_api model_var ()))
          () graph
        |> ignore
  in
  let view =
    let%arr model = model in
    let content =
      match page with
      | I18n.Notation -> notation_content ~lang
      | I18n.Home | I18n.Daily -> (
        match model with
      | Loading ->
          Vdom.Node.div
            ~attrs:[ Vdom.Attr.class_ "text-center py-5 text-secondary" ]
            [
              Vdom.Node.div
                ~attrs:
                  [ Vdom.Attr.class_ "spinner-border spinner-border-sm me-2" ]
                [];
              txt ~lang (I18n.loading_puzzle lang);
            ]
      | Error msg ->
          Vdom.Node.div
            ~attrs:[ Vdom.Attr.class_ "text-center py-5" ]
            [
              Vdom.Node.p
                ~attrs:
                  [
                    Vdom.Attr.class_ "text-danger";
                    Vdom.Attr.create "dir" "auto";
                  ]
                [ Vdom.Node.text msg ];
              Vdom.Node.button
                ~attrs:
                  [
                    Vdom.Attr.class_ "btn btn-outline-primary";
                    Vdom.Attr.on_click (fun _ ->
                        fetch_puzzle ~lang ~puzzle_api model_var ());
                  ]
                [ txt ~lang (I18n.retry lang) ];
            ]
      | Puzzle ui ->
          let p = ui.puzzle in
          let btn_label =
            if ui.awaiting_next then I18n.next_puzzle lang
            else I18n.check_answer lang
          in
          let btn_disabled =
            if ui.awaiting_next then false
            else ui.check_locked || ui.is_animating
          in
          let button_disabled_attrs =
            if btn_disabled then [ Vdom.Attr.disabled ] else []
          in
          let feedback_class =
            if String.is_empty ui.feedback then "mb-0"
            else if ui.feedback_ok then "mb-0 feedback-correct"
            else "mb-0 feedback-error"
          in
          Vdom.Node.div
            ~attrs:[ Vdom.Attr.class_ "row gx-4 gy-3" ]
            [
              Vdom.Node.div
                ~attrs:[ Vdom.Attr.class_ "col-md-5"; Vdom.Attr.id "board-col" ]
                [
                  Vdom.Node.div
                    ~attrs:
                      [
                        Vdom.Attr.id "board";
                        Vdom.Attr.create "style" "width:100%";
                      ]
                    [];
                ];
              Vdom.Node.div
                ~attrs:
                  [
                    Vdom.Attr.class_ "col-md-4 d-flex flex-column";
                    Vdom.Attr.id "moves-col";
                  ]
                [
                  Vdom.Node.p
                    ~attrs:[ Vdom.Attr.create "style" "margin-bottom:0.5rem" ]
                    [ txt ~lang (to_play_label ~lang p.fen) ];
                  move_rows ~model_var ~ui ~p;
                  Vdom.Node.div
                    ~attrs:[ Vdom.Attr.create "style" "margin-bottom:0.5rem" ]
                    [
                      Vdom.Node.button
                        ~attrs:
                          ([
                             Vdom.Attr.type_ "button";
                             Vdom.Attr.id "check-btn";
                             Vdom.Attr.on_click (fun _ ->
                                 handle_primary_button ~lang ~puzzle_api
                                   ~auto_advance model_var ());
                           ]
                          @ button_disabled_attrs)
                        [ txt ~lang btn_label ];
                    ];
                  Vdom.Node.p
                    ~attrs:
                      [
                        Vdom.Attr.id "feedback";
                        Vdom.Attr.class_ feedback_class;
                        Vdom.Attr.create "dir" "auto";
                      ]
                    [ Vdom.Node.text ui.feedback ];
                ];
            ])
    in
    Vdom.Node.div
      ~attrs:
        [
          Vdom.Attr.class_ "container-lg px-4";
          Vdom.Attr.create "dir" I18n.layout_dir;
        ]
      [ nav_row ~lang ~page; content ]
  in
  view graph

let main_component graph =
  let lang = I18n.from_pathname () in
  let page = I18n.page_from_pathname () in
  let puzzle_api = puzzle_api_for_page page in
  component ~lang ~page puzzle_api graph

let () =
  Bonsai_web.Start.start main_component ~bind_to_element_with_id:"app"
