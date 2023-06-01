open! Core
open! Lwt.Syntax
open! Lwt.Infix
open! Aux

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
}
[@@deriving fields, compare, sexp, stable_record ~version:Dbf.t ~remove:[ bbox; shape ]]

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
      tract_of_Dbf_t attribs ~bbox:shape.bbox ~shape)


(** Accepts a string and HTML encodes the string so that it can be embedded into an SVG element *)
let svg_encode s =
  String.substr_replace_all s ~pattern:"&" ~with_:"&amp;"

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
<text vertical-align="middle" text-anchor="middle" x="%d" y="%d" font-size="10px">%s</text>|svg}
        (svg_encode id) points fill
        (Float.iround_nearest_exn (!x_sum // Array.length ps))
        (Float.iround_nearest_exn (!y_sum // Array.length ps))
        (svg_encode tract.name))

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
let tracts_to_svg ~(width : int) ~height ?get_id ?get_fill bbox base_layer tracts =
  let polygons =
    Array.concat_map tracts ~f:(tract_to_svg_polygons ~width ~height ?get_id ?get_fill bbox)
    |> String.concat_array ~sep:"\n"
  in
  (* let base_image = Base64.encode_string 
  in *)
  sprintf
    {svg|<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">
  <image
    preserveAspectRatio="none"
    href="data:image/png;base64,%s" width="%d" height="%d" />
  %s
</svg>
|svg}
    width height width height base_layer width height polygons


type t = tract [@@deriving sexp]
