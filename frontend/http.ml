open Core
open Async_kernel
open Js_of_ocaml
open Js_of_ocaml.XmlHttpRequest

let get url =
  Deferred.create (fun ivar ->
      let xhr = create () in
      xhr##_open (Js.string "GET") (Js.string url) (Js.bool true);
      xhr##.onreadystatechange :=
        Js.wrap_callback (fun _ ->
            match xhr##.readyState with
            | XmlHttpRequest.DONE ->
                let code = xhr##.status in
                let body =
                  Js.Opt.case xhr##.responseText (fun () -> Js.string "") Fun.id
                in
                if not (Ivar.is_full ivar) then
                  Ivar.fill_exn ivar (code, Js.to_string body)
            | _ -> ());
      xhr##send Js.null)
  >>= fun (code, body) ->
  match code with 200 -> return (Ok body) | _ -> return (Error body)

let post url (body : string) =
  Deferred.create (fun ivar ->
      let xhr = create () in
      xhr##_open (Js.string "POST") (Js.string url) (Js.bool true);
      xhr##setRequestHeader (Js.string "Content-Type")
        (Js.string "application/json");
      xhr##.onreadystatechange :=
        Js.wrap_callback (fun _ ->
            match xhr##.readyState with
            | XmlHttpRequest.DONE ->
                let code = xhr##.status in
                let resp =
                  Js.Opt.case xhr##.responseText (fun () -> Js.string "") Fun.id
                in
                if not (Ivar.is_full ivar) then
                  Ivar.fill_exn ivar (code, Js.to_string resp)
            | _ -> ());
      xhr##send (Js.some (Js.string body)))
  >>= fun (code, body) ->
  match code with 200 | 201 -> return (Ok body) | _ -> return (Error body)
