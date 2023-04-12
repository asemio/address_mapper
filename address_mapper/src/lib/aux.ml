open! Core
open! Lwt.Syntax
open! Lwt.Infix

let verbose = ref false

let ( <| ) f g x = f (g x)

let orf ~f = function
| None -> false
| Some x -> f x

let overwrite_flags = Lwt_unix.[ O_WRONLY; O_NONBLOCK; O_CREAT; O_TRUNC ]

let read_flags = Lwt_unix.[ O_RDONLY; O_NONBLOCK ]

let write_to_file ~filename content =
  Lwt_io.with_file ~flags:overwrite_flags ~mode:Output filename (fun oc -> Lwt_io.fprint oc content)

let write_dbf_to_file sexp_of_t ~output input =
  Asemio_dbf.read input |> sprintf !"%{sexp: t}" |> write_to_file ~filename:output

let read_file ~filename =
  Lwt_io.with_file ~flags:read_flags ~mode:Input filename (fun ic -> Lwt_io.read ic)

module Range = struct
  type t = {
    lower: int;
    upper: int;
  }
  [@@deriving sexp]
end

let get_csv_stream filename =
  let* ic = Lwt_io.open_file ~flags:read_flags ~mode:Input filename in
  let+ csv = Csv_lwt.of_channel ~has_header:true ic in
  let headers = Csv_lwt.Rows.header csv in
  let stream =
    Lwt_stream.from (fun () ->
        Lwt.catch
          (fun () -> Csv_lwt.next csv >|= Option.return)
          (function
            | End_of_file ->
              (* automatically closes the underlying input channel *)
              let* () = Csv_lwt.close_in csv in
              Lwt.return_none
            | Csv.Failure (row, column, msg) ->
              failwiths ~here:[%here] msg (row, column) [%sexp_of: int * int]
            | exn -> raise exn))
  in
  headers, stream

let verbose_print msg = if !verbose then print_endline msg
