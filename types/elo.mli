(** [Elo] is the Elo rating of a user or puzzle. *)

open! Core

type t

include Intable.S with type t := t
