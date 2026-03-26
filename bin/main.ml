open! Core
open! Core_unix

let () = Command_unix.run Bonsai_chess.Server.command
