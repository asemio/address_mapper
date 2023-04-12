open! Core
open! Aux
include Shapefile

module Interval = struct
  type t = {
    lower: float;
    upper: float;
  }
  [@@deriving sexp]

  let overlap x y =
    let open Float in
    (x.lower <= y.lower && y.lower <= x.upper)
    || (x.lower <= y.upper && y.upper <= x.upper)
    || (y.lower <= x.lower && x.lower <= y.upper)
end

type d3m_bbox = D3M.bbox = {
  xmin: float;
  xmax: float;
  ymin: float;
  ymax: float;
  zmin: float;
  zmax: float;
  mmin: float;
  mmax: float;
}
[@@deriving sexp]

type header = Common.header = {
  length: int;
  version: int;
  shape_type: int;
  bbox: d3m_bbox;
}
[@@deriving sexp]

type point = D2.point = {
  x: float;
  y: float;
}
[@@deriving compare, equal, sexp]

module BBox = struct
  type t = D2.bbox = {
    xmin: float;
    xmax: float;
    ymin: float;
    ymax: float;
  }
  [@@deriving compare, sexp, yojson]

  (** Accepts a bounding box and returns its center *)
  let get_center { xmin; xmax; ymin; ymax } =
    Float.{ x = ((xmax - xmin) / 2.0) + xmin; y = ((ymax - ymin) / 2.0) + ymin }

  (** Returns true if the bounding box contains the given point *)
  let includes { xmin; xmax; ymin; ymax } { x; y } =
    Float.(xmin <= x && x <= xmax && ymin <= y && y <= ymax)

  (** Returns true iff two bounding boxes overlap. *)
  let overlaps x y =
    let open Interval in
    overlap { lower = x.xmin; upper = x.xmax } { lower = y.xmin; upper = y.xmax }
    && overlap { lower = x.ymin; upper = x.ymax } { lower = y.ymin; upper = y.ymax }

  let bbox_of_d3m ({ xmin : float; xmax : float; ymin : float; ymax : float; _ } : d3m_bbox) : t =
    { xmin; xmax; ymin; ymax }
end

type path = {
  bbox: BBox.t;
  points: point array;
}
[@@deriving sexp]

type matrix = float array array [@@deriving compare, sexp]

module Polygon = struct
  type t = {
    bbox: BBox.t;
    points: point array array;
  }
  [@@deriving compare, sexp]
end

type polyline = {
  bbox: BBox.t;
  points: point array array;
}
[@@deriving sexp]

type t =
  | Path of path
  | Poly of Polygon.t
  | Pline of polyline
[@@deriving sexp]

(**
  Accepts a shape and returns the associated shape.
*)
let of_shape = function
| Shp.Polygon (bbox, points) -> Poly { bbox; points }
| Shp.MultiPoint (bbox, points) -> Path { bbox; points }
| Shp.PolyLine (bbox, points) -> Pline { bbox; points }
| _ ->
  failwiths ~here:[%here] "Invalid shape. The shape is neither a path nor a polygon." () [%sexp_of: unit]

(**
  Accepts a shape and returns the associated polygon.

  Note: Shapefiles support multiple types of objects, but the Census
  Bureau only uses Polygons with 2D points.
*)
let polygon_of_shape = function
| Poly polygon -> polygon
| _ -> failwiths ~here:[%here] "Invalid shape. The shape is not a polygon." () [%sexp_of: unit]

(**
  Accepts a shape and returns the associated poly line.

  Note: the Census Edges Shapefile only uses multipoint lines.
*)
let pline_of_shape = function
| Pline pline -> pline
| _ -> failwiths ~here:[%here] "Invalid shape. The shape is not a poly line." () [%sexp_of: unit]

let read : string -> header * t list = Tuple2.map_snd ~f:(List.map ~f:of_shape) <| Shp.read

module Region = struct
  (**
    Represents polygonal regions.

    Note: we take the polyogonal region, select an internal point
    called the "center" point (which does not have to be the center),
    then triangulate the region. For each triangle, we compute a
    convex hull transformation matrix. This matrix projects a
    translated point into a space where the unit square represents the
    space inside the given triangle. We use these matrices to
    efficiently determine whether or not a given point is in the
    original polygon.
  *)
  type t = {
    center: float array;
    matrices: matrix array;
  }
  [@@deriving compare, sexp]

  (** Accepts an array of points and returns their geometric center. *)
  let get_points_center ps : point =
    let n = Array.length ps |> Float.of_int in
    let sum_x, sum_y =
      Array.fold ps ~init:(0.0, 0.0) ~f:(fun (sum_x, sum_y) { x; y } -> sum_x +. x, sum_y +. y)
    in
    { x = sum_x /. n; y = sum_y /. n }

  (**
    Accepts the center of a region defined by a sequence of points,
    accepts two sequential points, and returns their convex hull
    transformation matrix.
  *)
  let get_matrix center p0 p1 : matrix =
    let open Asemio_stats in
    let v0 = vector_sub [| p0.x; p0.y |] center in
    let v1 = vector_sub [| p1.x; p1.y |] center in
    matrix_inv [| [| v0.(0); v1.(0) |]; [| v0.(1); v1.(1) |] |]

  (**
    Accepts a polygon, "triangulates" the polygon, computes a convex
    hull transformation (CHT) matrix for each triangle, and returns
    the CHT matrices along with the center point.
  *)
  let of_polygon Polygon.{ bbox = _; points } =
    Array.map points ~f:(fun ps ->
        let n = Array.length ps in
        let center_pt = get_points_center ps in
        let center = [| center_pt.x; center_pt.y |] in
        let matrices = Queue.create ~capacity:n () in
        for i = 0 to n - 1 do
          (* at least one of the census tracts had a shape where the same vertex was repeated twice. *)
          let p, q = ps.(i), ps.(if i < n - 1 then i + 1 else 0) in
          if not @@ [%equal: point] p q then Queue.enqueue matrices (get_matrix center p q)
        done;
        { center; matrices = Queue.to_array matrices })

  let%expect_test "of_polygon_1" =
    of_polygon
      {
        bbox = BBox.{ xmin = 0.0; xmax = 0.0; ymin = 0.0; ymax = 0.0 };
        points =
          Float.
            [|
              [|
                { x = -2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
                { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
                { x = 2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
                { x = -2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
              |];
            |];
      }
    |> (function
         | [| { center = _; matrices } |] ->
           let open Asemio_stats in
           Some
             Float.
               [|
                 vector_matrix_mult matrices.(0) [| 1.0; 0.0 |];
                 vector_matrix_mult matrices.(0) [| 0.0; 1.0 |];
                 vector_matrix_mult matrices.(0) [| 0.0; -1.0 |];
                 vector_matrix_mult matrices.(0) [| -1.0; 0.0 |];
                 vector_matrix_mult matrices.(0) [| 1.0 / sqrt 2.0; 1.0 / sqrt 2.0 |];
                 vector_matrix_mult matrices.(0) [| -1.0 / sqrt 2.0; 1.0 / sqrt 2.0 |];
                 vector_matrix_mult matrices.(0) [| -2.0 / sqrt 2.0; 2.0 / sqrt 2.0 |];
               |]
         | _ -> None)
    |> printf !"%{sexp: (float array array) option}";
    [%expect
      {|
      (((-0.35355339059327379 0.35355339059327379)
        (0.35355339059327379 0.35355339059327379)
        (-0.35355339059327379 -0.35355339059327379)
        (0.35355339059327379 -0.35355339059327379) (0 0.5) (0.5 0) (1 0))) |}]

  (**
    Accents a centered point and a convex hull transformation matrix
    and returns true iff the given point lies within the region
    represented by the matrix.

    Note: this function accepts a "workspace" that is a "scratch"
    matrix to reduce the number unnecessary memory allocations which
    take time.
  *)
  let matrix_contains (workspace : float array) (matrix : matrix) p =
    Asemio_stats.vector_matrix_mult_cm matrix p workspace;
    match workspace with
    | [| kx; ky |] -> Float.(0.0 <= kx && 0.0 <= ky && kx + ky <= 1.0)
    | _ ->
      failwiths ~here:[%here]
        "An internal error occured. vector_matrix_mult should never return an array with more or less \
         than two elements."
        () [%sexp_of: unit]

  let%expect_test "matrix_contains_1" =
    let workspace = Array.create ~len:2 0.0 in
    of_polygon
      {
        bbox = BBox.{ xmin = 0.0; xmax = 0.0; ymin = 0.0; ymax = 0.0 };
        points =
          Float.
            [|
              [|
                { x = -2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
                { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
                { x = 2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
                { x = -2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
              |];
            |];
      }
    |> (function
         | [| { center = _; matrices } |] ->
           Some
             Float.
               [|
                 matrix_contains workspace matrices.(0) [| 1.0; 0.0 |];
                 matrix_contains workspace matrices.(0) [| 0.0; 1.0 |];
                 matrix_contains workspace matrices.(0) [| 0.0; -1.0 |];
                 matrix_contains workspace matrices.(0) [| -1.0; 0.0 |];
                 matrix_contains workspace matrices.(0) [| 1.0 / sqrt 2.0; 1.0 / sqrt 2.0 |];
                 matrix_contains workspace matrices.(0) [| -1.0 / sqrt 2.0; 1.0 / sqrt 2.0 |];
                 matrix_contains workspace matrices.(0) [| -2.0 / sqrt 2.0; 2.0 / sqrt 2.0 |];
                 matrix_contains workspace matrices.(0) [| 0.3827; 0.9239 |];
                 matrix_contains workspace matrices.(0) [| 0.0; 2.0 |];
               |]
         | _ -> None)
    |> printf !"%{sexp: (bool array) option}";
    [%expect {| ((false true false false true true true true false)) |}]

  (**
    Accepts three arguments: an internal "center" point in a polygonal
    region; an array of convex hull transformation matrices that
    represent the triagulation of the region; and a point; and returns
    true iff the point is in the given region.
  *)
  let contains workspace { center; matrices } p =
    let q = Asemio_stats.vector_sub [| p.x; p.y |] center in
    Array.exists matrices ~f:(fun m -> matrix_contains workspace m q)

  let%expect_test "contains_1" =
    let open Float in
    let workspace = Array.create ~len:2 0.0 in
    of_polygon
      {
        bbox =
          BBox.
            {
              xmin = -2.0 / sqrt 2.0;
              xmax = 2.0 / sqrt 2.0;
              ymin = -2.0 / sqrt 2.0;
              ymax = 2.0 / sqrt 2.0;
            };
        points =
          [|
            [|
              { x = -2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
              { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
              { x = 2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
              { x = -2.0 / sqrt 2.0; y = -2.0 / sqrt 2.0 };
            |];
          |];
      }
    |> (function
         | [| x |] ->
           Some
             [|
               contains workspace x { x = 0.0; y = 1.0 };
               contains workspace x { x = 0.0; y = 1.4 };
               contains workspace x { x = 0.0; y = 1.5 };
               contains workspace x { x = 0.3827; y = 0.9239 };
               contains workspace x { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
               contains workspace x { x = -1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
               contains workspace x { x = -2.0; y = 0.0 };
             |]
         | _ -> None)
    |> printf !"%{sexp: bool array option}";
    [%expect {| ((true true false true true true false)) |}]
end
