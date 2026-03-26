(** [Move] is a move in a chess puzzle, which may end with white moving. *)

open! Core
module Standard : T
module Castles : T

module One : sig
  type white = [ `white ]
  type black = [ `black ]
  type any = [ white | black ]

  type _ t =
    | Standard : Standard.t -> [> any ] t
    | Castles : Castles.t -> [> any ] t
    | Pass : [> white ] t
end

type t =
  | White of One.any One.t
  | Pair of { white : One.any One.t; black : One.black One.t }

val to_string : t -> string
val flatten : t list -> string list
val of_pgn : string -> t list Or_error.t
