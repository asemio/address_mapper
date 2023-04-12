open! Core
open! Lwt.Syntax
open! Lwt.Infix
open! Alcotest_lwt

let () = Lwt_main.run @@ run "All" []
