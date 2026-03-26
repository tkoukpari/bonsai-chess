open! Core
open! Import

type t

val create : unit -> (t, [> Caqti_error.load ]) result

val with_conn :
  t ->
  f:(Caqti_lwt.connection -> ('a, Caqti_error.t) Lwt_result.t) ->
  ('a, Caqti_error.t) Lwt_result.t
