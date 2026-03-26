open! Core
open! Import

type t = (Caqti_lwt.connection, Caqti_error.t) Caqti_lwt_unix.Pool.t

let connection_uri =
  Option.value_exn (Sys.getenv "DATABASE_URL") |> Uri.of_string

let create () =
  match Caqti_lwt_unix.connect_pool connection_uri with
  | Ok pool -> Ok (pool :> t)
  | Error e -> Error e

let with_conn pool ~f = Caqti_lwt_unix.Pool.use f pool
