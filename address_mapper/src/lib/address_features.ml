open! Core
open! Aux

module Parity = struct
  (** Used to designate which addresses are on a given side of a street. *)
  type t =
    | Even
    | Odd
    | Both
  [@@deriving sexp]

  let of_string = function
  | "" -> None
  | "E" -> Some Even
  | "O" -> Some Odd
  | "B" -> Some Both
  | x -> failwiths ~here:[%here] "Invalid parity code" x [%sexp_of: string]

  (** Accepts a number and a parity and returns true iff the number has the given parity. *)
  let has_parity x = function
  | Even -> x % 2 = 0
  | Odd -> x % 2 = 1
  | Both -> true
end

module Dbf = struct
  open Asemio_dbf

  (** Represents the sides of a street segment. *)
  type side = {
    house_numbers: Range.t;
    house_numbers_parity: Parity.t option;
  }
  [@@deriving sexp]

  (**
    Represents street segments bounded by census tract boundaries and
    other region boundaries

    Warning: the house number ranges are not guaranteed to be
    increasing. That depends on the orientation of the street segment.
  *)
  type t = {
    id: int; (* the address features's offset within the shapefile and dbf file. *)
    name: string;
    linear_id: string;
    left_side: side option;
    right_side: side option;
  }
  [@@deriving sexp]

  (**
    Accepts the address features DBF data and parses it.

    Warning: this function ignores those address ranges that have
    house numbers containing hyphens. These are a small minority of
    address.
  *)
  let get { header; columns } =
    let open Option.Let_syntax in
    let get_column = List.Assoc.find_exn columns ~equal:[%equal: string] in
    let ( names,
          linear_ids,
          house_numbers_left_parity,
          house_numbers_right_parity,
          house_numbers_left_lower,
          house_numbers_left_upper,
          house_numbers_right_lower,
          house_numbers_right_upper ) =
      ( get_column "FULLNAME" |> get_string,
        get_column "LINEARID" |> get_string,
        get_column "PARITYL" |> get_string,
        get_column "PARITYR" |> get_string,
        get_column "LFROMHN" |> get_string,
        get_column "LTOHN" |> get_string,
        get_column "RFROMHN" |> get_string,
        get_column "RTOHN" |> get_string )
    in
    Array.init header.nrecords ~f:(fun id : t ->
        {
          id;
          name = names.(id);
          linear_id = linear_ids.(id);
          left_side =
            (let%map house_numbers =
               let%bind lower = Asemio_dbf.int_of_string house_numbers_left_lower.(id) in
               let%map upper = Asemio_dbf.int_of_string house_numbers_left_upper.(id) in
               Range.{ lower; upper }
             in
             { house_numbers_parity = house_numbers_left_parity.(id) |> Parity.of_string; house_numbers });
          right_side =
            (let%map house_numbers =
               let%bind lower = Asemio_dbf.int_of_string house_numbers_right_lower.(id) in
               let%map upper = Asemio_dbf.int_of_string house_numbers_right_upper.(id) in
               Range.{ lower; upper }
             in
             { house_numbers_parity = house_numbers_right_parity.(id) |> Parity.of_string; house_numbers });
        })
end

module Side = struct
  (** Represents the sides of a street segment. *)
  type t = {
    house_numbers: Range.t;
    house_numbers_parity: Parity.t option;
    tract: Census_tract.t option;
  }
  [@@deriving fields, sexp, stable_record ~version:Dbf.side ~remove:[ tract ]]

  (**
    Accepts an address and a street segment side and returns true iff
    the address lies within the address range associated with the
    side.

    WARNING: if the street segment side does not have an address
    parity, this function returns false.
  *)
  let address_on_side address { house_numbers; house_numbers_parity; _ } =
    house_numbers.lower <= address
    && address <= house_numbers.upper
    && Option.value_map house_numbers_parity ~default:false ~f:(Parity.has_parity address)
end

(** Represents street segments. *)
type t = {
  id: int; (* the address features's offset within the shapefile and dbf file. *)
  name: string;
  linear_id: string;
  center: Shape.point;
  left_side: Side.t option;
  right_side: Side.t option;
}
[@@deriving
  fields, sexp, stable_record ~version:Dbf.t ~remove:[ center ] ~modify:[ left_side; right_side ]]

(**
    Apply standard transformations to road names to reduce the rate of
    false negatives when matching address road names.
  *)
let canonicalize_street_name name =
  String.lowercase name
  |> String.filter ~f:(fun c -> not @@ List.mem [ ','; '.'; '#' ] c ~equal:[%equal: char])
  |> fun init ->
  List.fold
    [
      "-", " ";
      "first", "fst";
      "second", "snd";
      "third", "thd";
      "street", "st";
      "road", "rd";
      "avenue", "ave";
      "place", "pl";
      "drive", "dr";
      "boulevard", "blvd";
      "north", "n";
      "east", "e";
      "west", "w";
      "south", "s";
      " th", "th";
      "nbr", "apt";
    ]
    ~init
    ~f:(fun acc (pattern, with_) -> String.substr_replace_all acc ~pattern ~with_)

(*
  A two dimensional vector that is used for scratch calculations to
  minimize the number of memory allocations performed when determining
  which census tract contains various points.
*)
let create_workspace () = Array.create_float_uninitialized ~len:2

(**
  Accepts a 2D vector and returns two points offset from the center
  (orthogonally) delta units away. The points are returned as rows in
  a two by two matrix.

  Note: this function is used to generate test points to determine
  which census tract contains a given street segment.
*)
let get_segment_points delta (x : float array) =
  let open Float in
  let open Asemio_stats in
  let midpoint = vector_scalar_mult 0.5 x in
  let norm = vector_norm x in
  [|
    (* left point *)
    vector_matrix_mult [| [| 0.0; -delta / norm |]; [| delta / norm; 0.0 |] |] x |> vector_add midpoint;
    (* right point *)
    vector_matrix_mult [| [| 0.0; delta / norm |]; [| -delta / norm; 0.0 |] |] x |> vector_add midpoint;
  |]

let%expect_test "get_segment_points_1" =
  get_segment_points 1.0 [| 1.0; 0.0 |] |> printf !"%{sexp: float array array}";
  [%expect {| ((0.5 1) (0.5 -1)) |}]

let%expect_test "get_segment_points_2" =
  get_segment_points 1.0 [| 0.0; 1.0 |] |> printf !"%{sexp: float array array}";
  [%expect {| ((-1 0.5) (1 0.5)) |}]

let%expect_test "get_segment_points_3" =
  get_segment_points 0.1 [| 0.0; -1.0 |] |> printf !"%{sexp: float array array}";
  [%expect {| ((0.1 -0.5) (-0.1 -0.5)) |}]

let%expect_test "get_segment_points_4" =
  let open Float in
  get_segment_points 0.5 [| 1.0 / sqrt 2.0; -1.0 / sqrt 2.0 |] |> printf !"%{sexp: float array array}";
  [%expect
    {|
    ((0.70710678118654746 5.5511151231257827E-17)
     (-5.5511151231257827E-17 -0.70710678118654746)) |}]

(** Stores the total number of road segments that the program has processed. *)
let num_segments_processed = ref 0

(**
  Accepts the shapefiles for each address feature along with their
  attributes and combines them into a composite data structure that
  represents the road segment.
*)
let get workspace (tracts : Census_tract.Lookup.t) (attribs : Dbf.t array) (shapes : Shape.t array) =
  (*
    one degree of latitude/longitude approximately equals 1nm (6076
    feet) - hence delta is roughly 11 meters

    https://www.usna.edu/Users/oceano/pguth/md_help/html/approx_equivalents.htm
  *)
  let delta = 0.0001 in
  verbose_print @@ sprintf "Indexing %d street segments.\n" (Array.length shapes);
  Array.map2_exn attribs shapes ~f:(fun attribs s ->
      if !num_segments_processed % 1000 = 0
      then verbose_print @@ sprintf "Indexed %d street segments.\n" !num_segments_processed;
      incr num_segments_processed;
      let pline = Shape.pline_of_shape s in
      let center : Shape.point = Shape.BBox.get_center pline.bbox in
      let left_tract, right_tract =
        (* all of the polylines in the dataset have only a single path - hence we can hardcode a reference the first. *)
        if Array.length pline.points.(0) < 2
        then (* strangely 61 linear features are defined by a single point. *)
          None, None
        else (
          let first_point = [| pline.points.(0).(0).x; pline.points.(0).(0).y |] in
          let last_point = [| pline.points.(0).(1).x; pline.points.(0).(1).y |] in
          let translation_matrix = [| first_point; first_point |] in
          let ref_points =
            Asemio_stats.vector_sub last_point first_point
            |> get_segment_points delta
            |> Asemio_stats.matrix_add translation_matrix
          in
          ( Census_tract.Lookup.find_tract_aux workspace
              { x = ref_points.(0).(0); y = ref_points.(0).(1) }
              tracts,
            Census_tract.Lookup.find_tract_aux workspace
              { x = ref_points.(1).(0); y = ref_points.(1).(1) }
              tracts ))
      in
      of_Dbf_t attribs ~center
        ~modify_left_side:(Option.map ~f:(Side.of_Dbf_side ~tract:left_tract))
        ~modify_right_side:(Option.map ~f:(Side.of_Dbf_side ~tract:right_tract)))

(**
  Accepts an array of street segments and indexes them by canonical
  road name.

  Note: The resulting table can be used to efficiently, find the
  street segment that a given address belongs to.
*)
let get_segment_map segs =
  let segments = String.Table.create () in
  let index = String.Table.create () in
  Array.iter segs ~f:(fun x -> String.Table.add_multi segments ~key:x.name ~data:x);
  String.Table.iteri segments ~f:(fun ~key ~data ->
      Postal.parse key
      |> Postal.AddressSet.iter ~f:(function
           | Postal.Address.{ road = Some road; _ } ->
             canonicalize_street_name road
             |> String.Table.update index ~f:(function
                  | None -> data
                  | Some segments -> data @ segments)
           | _ -> ()));
  index

(**
  Accepts a segments lookup tree and an address and returns the census
  tract that contains the address.
*)
let get_segment_tract segments address =
  let open Option in
  let canonical_addresses = Postal.parse address in
  Postal.AddressSet.find_map canonical_addresses ~f:(function
    | Postal.Address.{ road = Some road; house_number = Some house_number; _ } -> (
      let num_opt =
        try Some (Int.of_string house_number) with
        | Failure _ -> None
      in
      match num_opt with
      | None -> None
      | Some num ->
        canonicalize_street_name road
        |> String.Table.find segments
        >>= List.find_map ~f:(fun segment ->
                match segment.left_side, segment.right_side with
                | Some side, _ when Side.address_on_side num side ->
                  (* print_endline @@ sprintf !"%{sexp: Census_tract.t option}" side.tract; *)
                  side.tract
                | _, Some side when Side.address_on_side num side ->
                  (* print_endline @@ sprintf !"%{sexp: Census_tract.t option}" side.tract; *)
                  side.tract
                | _, _ ->
                  (* print_endline "no match"; *)
                  None))
    | _ -> None)
