open! Core
open! Lwt.Syntax
open! Lwt.Infix
open! Aux

let num_lookup_sectors = ref 0

let lookup_sectors_sum_width = ref 0.0

module Dbf = struct
  open Asemio_dbf

  type t = {
    id: int;
    name: string;
  }
  [@@deriving sexp]

  (**
    Accepts the data read from a Census Tract Database ( *.dbf) file and
    returns the information about the census tracts described in the
    file.
  *)
  let get column_name { header; columns } =
    let get_column = List.Assoc.find_exn columns ~equal:[%equal: string] in
    let names = get_column column_name |> get_string in
    Array.init header.nrecords ~f:(fun id : t -> { id; name = names.(id) })
end

module Shape = struct
  include Shape

  (**
    Accepts one argument: file_path, a file system path pointing to the
    ESRI Shapefile that contains the boundaries points of the census
    tracts.

    Note: this file U.S. Census Bureau publishes Shapefiles that
    define the geographic boundaries for census tracts. You can find
    these files here:

    https://www.census.gov/cgi-bin/geo/shapefiles/index.php

    You can find additional documentation about these shapefiles here:

    https://www.census.gov/programs-surveys/geography/technical-documentation/complete-technical-documentation/tiger-geo-line.html.
  *)
  let read : string -> header * Polygon.t array =
    Tuple2.map_snd ~f:(Array.of_list_map ~f:polygon_of_shape) <| Shape.read
end

(** Represents census tracts and their geographic regions. *)
type tract = {
  id: int;
  name: string;
  bbox: Shape.BBox.t;
  shape: Shape.Polygon.t;
  regions: Geometry.Region.t array;
}
[@@deriving fields, compare, sexp, stable_record ~version:Dbf.t ~remove:[ bbox; shape; regions ]]

module Set = Set.Make (struct
  type t = tract [@@deriving compare, sexp]
end)

(**
  Accepts two arguments: an array of census tract attribute records
  and an array of census tract polygons; and returns an array of
  census tract records.
*)
let get (attribs : Dbf.t array) (shapes : Shape.Polygon.t array) =
  Array.map2_exn attribs shapes ~f:(fun attribs shape ->
      tract_of_Dbf_t attribs ~bbox:shape.bbox ~shape ~regions:(Shape.Region.of_polygon shape))

(**
  Accepts six arguments:

  * width - the width of the SVG image in pixels
  * height - the height of the SVG image in pixels
  * get_id - an optional function that takes a tract and returns an SVG
    element ID
  * get_fill - an optional function that takes a tract and returns a string
    that represents its fill color
  * bbox - the bounding box that gives the longitudinal and
    latitudinal boundaries of the area mapped in the SVG image
  * tract - the census tract that is being drawn

  and returns SVG polygons that represent the given census tract.
*)
let tract_to_svg_polygons ~width ~height ?get_id ?get_fill Shape.BBox.{ xmin; xmax; ymin; ymax }
   ({ shape = Shape.Polygon.{ points; _ }; _ } as tract) =
  let hscale, wscale = (ymax -. ymin) /. float height, (xmax -. xmin) /. float width in
  let fill =
    match get_fill with
    | None -> "none"
    | Some f -> f tract
  in
  Array.mapi points ~f:(fun i ps ->
      let x_sum, y_sum = ref 0, ref 0 in
      let points =
        Array.map ps ~f:(fun Shape.{ x; y } ->
            let x_coord, y_coord =
              ( Float.iround_nearest_exn ((x -. xmin) /. wscale),
                Float.iround_nearest_exn ((ymax -. y) /. hscale) )
            in
            x_sum := !x_sum + x_coord;
            y_sum := !y_sum + y_coord;
            sprintf "%d,%d" x_coord y_coord)
        |> String.concat_array ~sep:" "
      in
      let id =
        match get_id with
        | None -> ""
        | Some f -> sprintf {svg| id="%s"|svg} (f i tract)
      in
      sprintf
        {svg|<polygon%s points="%s" fill="%s" stroke="black" />
<text vertical-align="middle" text-anchor="middle" x="%d" y="%d" font-size="2px">%s</text>|svg}
        id points fill
        (Float.iround_nearest_exn (!x_sum // Array.length ps))
        (Float.iround_nearest_exn (!y_sum // Array.length ps))
        tract.name)

(**
  Accepts six arguments:

  * width - the width of the SVG image in pixels
  * height - the height of the SVG image in pixels
  * get_id - an optional function that takes a tract and returns an SVG
    element ID
  * get_fill - an optional function that takes a tract and returns a string
    that represents its fill color
  * bbox - the bounding box that gives the longitudinal and
    latitudinal boundaries of the area mapped in the SVG image
  * base_layer_url - a URL to a PNG, JPG, or SVG file that represents
    the underlying map that the census tracts will be drawn on.
  * tracts - the census tracts that are being drawn

  and returns an SVG string that represent the given census tracts.
*)
let tracts_to_svg ~(width : int) ~height ?get_id ?get_fill bbox base_layer_url tracts =
  let polygons =
    Array.concat_map tracts ~f:(tract_to_svg_polygons ~width ~height ?get_id ?get_fill bbox)
    |> String.concat_array ~sep:"\n"
  in
  sprintf
    {svg|<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">
  <image href="%s" width="%d" height="%d" />
  %s
</svg>
|svg}
    width height width height base_layer_url width height polygons

(**
  Defines a datastructure for the efficient lookup of the census
  tract that contains a speciific location.
*)
module Lookup = struct
  type 'a node = {
    bbox: Shape.BBox.t;
    children: 'a array;
  }
  [@@deriving sexp]

  type leaf = {
    bbox: Shape.BBox.t;
    children: tract Queue.t;
  }
  [@@deriving sexp]

  type t =
    | Node of t node
    | Leaf of leaf
  [@@deriving sexp]

  (**
    Accepts a lookup tree and returns the average number of census
    tracts linked to each leaf.
  *)
  let get_num_tracts_per_leaf x =
    let rec aux ((num_leaves, tbl) as acc) = function
      | Node { bbox = _; children } -> Array.fold children ~init:acc ~f:aux
      | Leaf { bbox = _; children } ->
        ( num_leaves + 1,
          Queue.length children
          |> Map.update tbl ~f:(function
               | None -> 1
               | Some n -> n + 1) )
    in
    let _num_leaves, tbl = aux (0, Int.Map.empty) x in
    (* Int.Map.fold tbl ~init:0.0 ~f:(fun ~key ~data acc -> acc +. (data * key // num_leaves)) *)
    tbl

  (**
    Efficiently streams an S-Expression to the output channel that
    represents the given Lookup table.
  *)
  let stream_to_oc lookup oc =
    let space n = String.make n ' ' in
    let rec loop indent acc = function
      | Leaf leaf ->
        let* () = acc in
        Lwt_io.write_line oc (sprintf !"%{space}%{sexp: leaf}" indent leaf)
      | Node { bbox; children } ->
        let* () = acc in
        let acc = Lwt_io.write_line oc (sprintf !"%{space}%{sexp: Shape.BBox.t}(" indent bbox) in
        let* () = Array.fold children ~init:acc ~f:(fun acc child -> loop (indent + 2) acc child) in
        Lwt_io.write_line oc (sprintf !"%{space})" indent)
    in
    loop 0 Lwt.return_unit lookup

  let stream_to_file filename =
    Lwt_io.with_file ~flags:overwrite_flags ~mode:Output filename <| stream_to_oc

  (** Accepts a bounding box that defines a region and divides it into four quadrants. *)
  let get_quadrants bbox =
    let center = Shape.BBox.get_center bbox in
    Array.init 4 ~f:(fun i ->
        match i with
        | 0 ->
          (* top left quadrant *)
          Shape.BBox.{ xmin = bbox.xmin; xmax = center.x; ymin = bbox.ymin; ymax = center.y }
        | 1 ->
          (* top right quadrant *)
          Shape.BBox.{ xmin = center.x; xmax = bbox.xmax; ymin = bbox.ymin; ymax = center.y }
        | 2 ->
          (* bottom left quadrant *)
          Shape.BBox.{ xmin = bbox.xmin; xmax = center.x; ymin = center.y; ymax = bbox.ymax }
        | 3 ->
          (* bottom right quadrant *)
          Shape.BBox.{ xmin = center.x; xmax = bbox.xmax; ymin = center.y; ymax = bbox.ymax }
        | _ -> failwiths ~here:[%here] "An internal error has occured" () [%sexp_of: unit])

  let rec create_lookup_tree_aux quadrants depth =
    Array.init 4 ~f:(fun i ->
        match depth with
        | depth when depth > 0 ->
          let bbox = quadrants.(i) in
          let children = create_lookup_tree_aux (get_quadrants bbox) (depth - 1) in
          Node { bbox; children }
        | _ ->
          incr num_lookup_sectors;
          lookup_sectors_sum_width :=
            !lookup_sectors_sum_width +. ((quadrants.(i).xmax -. quadrants.(i).xmin) /. 2.0);
          Leaf { bbox = quadrants.(i); children = Queue.create () })

  (** Creates an empty lookup tree *)
  let create_lookup_tree bbox depth =
    Node { bbox; children = create_lookup_tree_aux (get_quadrants bbox) depth }

  (** Accepts a census tract and adds it to the lookup tree. *)
  let rec add_tract (tract : tract) : t -> unit = function
  | Node { bbox; children } when Shape.BBox.overlaps bbox tract.bbox ->
    Array.iter children ~f:(add_tract tract)
  | Leaf { bbox; children } when Shape.BBox.overlaps bbox tract.bbox -> Queue.enqueue children tract
  | _ -> ()

  (**
    Accepts a Census Tracts header and an array of tracts, creates a
    lookup table, and adds the census tracts to the table.
  *)
  let get_lookup_table depth (header : Shape.header) tracts =
    let lookup_tree = create_lookup_tree (Shape.BBox.bbox_of_d3m header.bbox) depth in
    Array.iter tracts ~f:(fun tract -> add_tract tract lookup_tree);
    lookup_tree

  let rec find_tract_aux workspace point = function
  | Node { bbox; children } when Shape.BBox.includes bbox point ->
    Array.find_map children ~f:(find_tract_aux workspace point)
  | Leaf { bbox; children } when Shape.BBox.includes bbox point ->
    (* printf !"[find_tract_aux] children: %d\n" (Queue.length children); *)
    Queue.find_map children ~f:(fun tract ->
        Option.some_if
          (* Note: the convex hull algorithm is very fast and is sufficient to rule out approximately 20% of checks. *)
          (Array.exists tract.regions ~f:(fun region -> Shape.Region.contains workspace region point)
          && Geometry.internal tract.shape point)
          tract)
  | _ -> None

  let find_tract = find_tract_aux (Array.create_float_uninitialized ~len:2)
end

type t = tract [@@deriving sexp]
