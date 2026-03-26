open Core

type lang = Fa | En
type page = Home | Daily | Notation

let from_pathname () =
  let w = Js_of_ocaml.Js.Unsafe.pure_js_expr "window" in
  let loc = Js_of_ocaml.Js.Unsafe.get w (Js_of_ocaml.Js.string "location") in
  let path =
    Js_of_ocaml.Js.to_string
      (Js_of_ocaml.Js.Unsafe.get loc (Js_of_ocaml.Js.string "pathname"))
  in
  let parts =
    String.split path ~on:'/'
    |> List.filter ~f:(fun s -> not (String.is_empty s))
  in
  match parts with "fa" :: _ -> Fa | _ -> En

let page_from_pathname () =
  let w = Js_of_ocaml.Js.Unsafe.pure_js_expr "window" in
  let loc = Js_of_ocaml.Js.Unsafe.get w (Js_of_ocaml.Js.string "location") in
  let path =
    Js_of_ocaml.Js.to_string
      (Js_of_ocaml.Js.Unsafe.get loc (Js_of_ocaml.Js.string "pathname"))
  in
  let parts =
    String.split path ~on:'/'
    |> List.filter ~f:(fun s -> not (String.is_empty s))
  in
  match parts with
  | "fa" :: "daily" :: _ | "en" :: "daily" :: _ | "daily" :: _ -> Daily
  | "fa" :: "notation" :: _ | "en" :: "notation" :: _ | "notation" :: _ ->
      Notation
  | _ -> Home

let lang_switch_href ~current_lang ~page =
  match (current_lang, page) with
  | Fa, Home -> "/"
  | Fa, Daily -> "/daily"
  | Fa, Notation -> "/notation"
  | En, Home -> "/fa"
  | En, Daily -> "/fa/daily"
  | En, Notation -> "/fa/notation"

let lang_switch_label = function Fa -> "English" | En -> "فارسی"
let nav_puzzles = function Fa -> "معماها" | En -> "Puzzles"
let nav_daily = function Fa -> "روزانه" | En -> "Daily"
let nav_notation = function Fa -> "نماد نوشتاری" | En -> "Notation"
let href_puzzles = function Fa -> "/fa" | En -> "/"
let href_daily = function Fa -> "/fa/daily" | En -> "/daily"
let href_notation = function Fa -> "/fa/notation" | En -> "/notation"

let loading_puzzle = function
  | Fa -> "در حال بارگذاری معما…"
  | En -> "Loading puzzle…"

let retry = function Fa -> "تلاش دوباره" | En -> "Retry"
let check_answer = function Fa -> "بررسی پاسخ" | En -> "Check answer"
let next_puzzle = function Fa -> "معمای بعدی" | En -> "Next puzzle"

let to_play_white = function Fa -> "نوبت سپید است" | En -> "White to play"

let to_play_black = function Fa -> "نوبت سیاه است" | En -> "Black to play"

let enter_all_moves n = function
  | Fa -> sprintf "هر %d حرکت را به صورت SAN وارد کنید." n
  | En -> sprintf "Enter all %d moves (SAN)." n

let cannot_reach_server = function
  | Fa -> "اتصال به سرور برقرار نشد."
  | En -> "Cannot reach server."

let invalid_response = function
  | Fa -> "پاسخ نامعتبر از سرور"
  | En -> "Invalid response"

let correct_well_done = function
  | Fa -> "درست است! آفرین."
  | En -> "Correct! Well done."

let incorrect_try_again = function
  | Fa -> "اشتباه است. دوباره تلاش کنید."
  | En -> "Incorrect. Try again."

let could_not_load_next = function
  | Fa -> "معمای بعدی بار نشد."
  | En -> "Could not load next puzzle."

let html_lang = function Fa -> "fa" | En -> "en"
let layout_dir = "ltr"
