open! Core
open! Import
open Lwt.Syntax
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type puzzle_result_request = { moves : string list; puzzle_id : int }
[@@deriving of_yojson]

type response =
  | Direct of Cohttp.Code.status * Cohttp.Header.t * Cohttp_lwt.Body.t
  | File of string

let validate_solution ~fen ~expected_moves user_moves =
  let user_sans =
    user_moves |> List.map ~f:String.strip
    |> List.filter ~f:(fun m -> not (String.is_empty m))
  in
  let expected_sans = Move.flatten expected_moves in
  if List.length user_sans <> List.length expected_sans then
    ( false,
      Some
        (Printf.sprintf "Wrong number of moves. Expected %d, got %d."
           (List.length expected_sans)
           (List.length user_sans)) )
  else
    try
      let rec loop i current_fen = function
        | [], [] -> (true, None)
        | user_san :: user_rest, expected_san :: expected_rest -> (
            let user_board = Cpp_chess.create_exn current_fen in
            match Cpp_chess.push_san user_board user_san with
            | Error e ->
                let msg = Error.to_string_hum e in
                let err_msg =
                  if String.is_substring msg ~substring:"invalid" then
                    Printf.sprintf "Invalid syntax at move %d: \"%s\"" (i + 1)
                      user_san
                  else if String.is_substring msg ~substring:"illegal" then
                    Printf.sprintf "Illegal move at move %d: \"%s\"" (i + 1)
                      user_san
                  else if String.is_substring msg ~substring:"ambiguous" then
                    Printf.sprintf "Ambiguous move at move %d: \"%s\"" (i + 1)
                      user_san
                  else
                    Printf.sprintf "Invalid move at move %d: \"%s\"" (i + 1)
                      user_san
                in
                (false, Some err_msg)
            | Ok () -> (
                let expected_board = Cpp_chess.create_exn current_fen in
                match Cpp_chess.push_san expected_board expected_san with
                | Error _ ->
                    (false, Some "Puzzle data error: invalid expected move.")
                | Ok () ->
                    let user_fen = Cpp_chess.fen user_board in
                    let expected_fen = Cpp_chess.fen expected_board in
                    if String.( <> ) user_fen expected_fen then
                      (false, Some "Incorrect. Try again.")
                    else loop (i + 1) expected_fen (user_rest, expected_rest)))
        | _ -> (false, Some "Wrong number of moves.")
      in
      loop 0 fen (user_sans, expected_sans)
    with _ -> (false, Some "Invalid puzzle position.")

let add_cors_headers (status, headers, body) =
  let headers =
    Cohttp.Header.add_list headers
      [
        ("Access-Control-Allow-Origin", "*");
        ("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
        ("Access-Control-Allow-Headers", "Content-Type, Authorization");
      ]
  in
  (status, headers, body)

let json_response ?(status = `OK) obj =
  let body = Yojson.Safe.to_string obj in
  ( status,
    Cohttp.Header.init_with "Content-Type" "application/json",
    `String body )

let error_json ?(status = `Internal_server_error) msg =
  json_response ~status (`Assoc [ ("error", `String msg) ])

let direct (status, headers, body) = Lwt.return (Direct (status, headers, body))

let handle_get_puzzle ~db _body =
  let* puzzle = Puzzle.random ~db in
  match puzzle with
  | Error e -> direct (error_json (Caqti_error.show e))
  | Ok None ->
      direct (error_json ~status:`Internal_server_error "No puzzles available")
  | Ok (Some p) -> direct (json_response (Puzzle.to_yojson p))

let handle_get_puzzle_daily ~db _body =
  let* puzzle = Puzzle.daily ~db in
  match puzzle with
  | Error e -> direct (error_json (Caqti_error.show e))
  | Ok None ->
      direct (error_json ~status:`Internal_server_error "No puzzles available")
  | Ok (Some p) -> direct (json_response (Puzzle.to_yojson p))

let handle_puzzle_result ~db body =
  match
    try
      Ok (body |> Yojson.Safe.from_string |> puzzle_result_request_of_yojson)
    with
    | Yojson.Json_error _ -> Error "Invalid JSON"
    | Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error (e, _) ->
        Error (Exn.to_string e)
  with
  | Error msg -> direct (error_json ~status:`Bad_request msg)
  | Ok { moves; puzzle_id = pid } -> (
      let* puzzle = Puzzle.get ~db pid in
      match puzzle with
      | Error e -> direct (error_json (Caqti_error.show e))
      | Ok None -> direct (error_json ~status:`Not_found "puzzle not found")
      | Ok (Some p) ->
          let correct, error =
            validate_solution
              ~fen:(Fen.to_string p.Puzzle.fen)
              ~expected_moves:p.Puzzle.moves moves
          in
          let payload =
            match error with
            | None -> [ ("correct", `Bool correct) ]
            | Some err -> [ ("correct", `Bool correct); ("error", `String err) ]
          in
          direct (json_response (`Assoc payload)))

let add_cors_to_direct (status, headers, body) =
  let s, h, b = add_cors_headers (status, headers, body) in
  Direct (s, h, b)

let serve_static ~web_dir path_parts =
  let path = String.concat ~sep:"/" path_parts in
  if String.is_empty path || String.equal path "index.html" then
    Lwt.return (File (Filename.concat web_dir "index.html"))
  else
    let file_path = Filename.concat web_dir path in
    if Sys_unix.file_exists_exn file_path then
      let stat = Caml_unix.stat file_path in
      if Poly.( = ) stat.st_kind Caml_unix.S_REG then
        Lwt.return (File file_path)
      else
        Lwt.return
          (Direct (`Not_found, Cohttp.Header.init (), `String "Not found"))
    else
      Lwt.return
        (Direct (`Not_found, Cohttp.Header.init (), `String "Not found"))

let router ~web_dir ~db req body =
  let uri = req |> Cohttp.Request.uri in
  let path = Uri.path uri in
  let meth = req |> Cohttp.Request.meth in
  let path_parts = String.split path ~on:'/' in
  let path_parts = List.filter path_parts ~f:(fun s -> String.(s <> "")) in
  match (meth, path_parts) with
  | `OPTIONS, _ ->
      Lwt.return (add_cors_to_direct (`OK, Cohttp.Header.init (), `String ""))
  | `GET, [ "api"; "puzzle" ] ->
      let* resp = handle_get_puzzle ~db body in
      Lwt.return
        (match resp with
        | Direct (s, h, b) -> add_cors_to_direct (s, h, b)
        | File _ -> resp)
  | `GET, [ "api"; "puzzle"; "daily" ] ->
      let* resp = handle_get_puzzle_daily ~db body in
      Lwt.return
        (match resp with
        | Direct (s, h, b) -> add_cors_to_direct (s, h, b)
        | File _ -> resp)
  | `POST, [ "api"; "puzzle"; "result" ] ->
      let* body_str = Cohttp_lwt.Body.to_string body in
      let* resp = handle_puzzle_result ~db body_str in
      Lwt.return
        (match resp with
        | Direct (s, h, b) -> add_cors_to_direct (s, h, b)
        | File _ -> resp)
  | `GET, [] | `GET, [ "" ] -> serve_static ~web_dir [ "index.html" ]
  | `GET, [ "daily" ] -> Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "notation" ] ->
      Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "fa" ] -> Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "fa"; "daily" ] ->
      Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "fa"; "notation" ] ->
      Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "en" ] -> Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "en"; "daily" ] ->
      Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, [ "en"; "notation" ] ->
      Lwt.return (File (Filename.concat web_dir "index.html"))
  | `GET, path_parts ->
      if List.mem path_parts "api" ~equal:String.equal then
        Lwt.return
          (Direct (`Not_found, Cohttp.Header.init (), `String "Not found"))
      else serve_static ~web_dir path_parts
  | _ ->
      Lwt.return
        (Direct (`Not_found, Cohttp.Header.init (), `String "Not found"))

let callback ~web_dir ~db _conn req body =
  let* resp = router ~web_dir ~db req body in
  match resp with
  | Direct (status, headers, body) ->
      Cohttp_lwt_unix.Server.respond
        ~status:(status :> Cohttp.Code.status_code)
        ~headers ~body ()
  | File path -> Cohttp_lwt_unix.Server.respond_file ~fname:path ()

let cohttp_on_exn = function
  | Caml_unix.Unix_error ((Caml_unix.ECONNRESET | Caml_unix.EPIPE), _, _) -> ()
  | Caml_unix.Unix_error (_error, _func, _arg) -> ()
  | _exn -> ()

let run_server ~web_dir port =
  match Db.create () with
  | Error _e -> Stdlib.exit 1
  | Ok db ->
      Lwt_main.run
        (let server =
           Cohttp_lwt_unix.Server.make ~callback:(callback ~web_dir ~db) ()
         in
         Cohttp_lwt_unix.Server.create ~on_exn:cohttp_on_exn
           ~mode:(`TCP (`Port port))
           server)

let command =
  Command.basic_spec ~summary:"Start the Bonsai Chess HTTP server"
    Command.Spec.empty (fun () ->
      let port =
        match Sys.getenv "PORT" with
        | None -> 8080
        | Some s -> ( try Int.of_string s with _ -> 8080)
      in
      run_server ~web_dir:"web" port)
