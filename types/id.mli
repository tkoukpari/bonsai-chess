(** [Id] is a unique identifier for a puzzle. *)

open! Core

type t

include Intable.S with type t := t
