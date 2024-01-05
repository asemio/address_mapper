open! Core
open! Aux
include Shape

module Segment = struct
  (**
    Represents a line segment.
  *)
  type t = {
    start_point: point;
    end_point: point;
  }
  [@@deriving sexp]

  (**
    Accepts a segment and a point and returns the scaling factor
    from the segment's start point to the given point iff the point is
    collinear.
  *)
  let[@inline] collinear_point (s : t) (p : point) =
    let open Float in
    let dx = s.end_point.x - s.start_point.x in
    let dy = s.end_point.y - s.start_point.y in
    match dx, dy with
    | 0.0, 0.0 ->
      failwiths ~here:[%here] "Invalid segment. The segment's start and end points are the same." ()
        [%sexp_of: unit]
    | 0.0, dy ->
      let ky = (p.y - s.start_point.y) / dy in
      Option.some_if ([%equal: float] (p.x - s.start_point.x) 0.0) ky
    | dx, 0.0 ->
      let kx = (p.x - s.start_point.x) / dx in
      Option.some_if ([%equal: float] (p.y - s.start_point.y) 0.0) kx
    | dx, dy ->
      let kx = (p.x - s.start_point.x) / dx in
      let ky = (p.y - s.start_point.y) / dy in
      Option.some_if ([%equal: float] kx ky) kx

  let%expect_test "collinear_point" =
    let open Float in
    [|
      collinear_point
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 0.0; y = 1.0 } }
        { x = 0.0; y = 0.0 };
      collinear_point
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 0.0 } }
        { x = 1.0; y = 0.0 };
      collinear_point
        {
          start_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
          end_point = { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
        }
        { x = 0.0; y = 0.0 };
      collinear_point
        {
          start_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
          end_point = { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
        }
        { x = 3.0 / sqrt 2.0; y = 3.0 / sqrt 2.0 };
      collinear_point
        {
          start_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
          end_point = { x = 2.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
        }
        { x = 3.0 / sqrt 2.0; y = 2.0 / sqrt 2.0 };
    |]
    |> printf !"%{sexp: float option array}";
    [%expect {| ((0) (1) (-1) (2) ()) |}]

  (**
    Accepts two segments and returns true iff they are collinear and s0 has an endpoint on s1.
  *)
  let[@inline] collinear_overlap s0 s1 =
    let open Float in
    match collinear_point s1 s0.start_point, collinear_point s1 s0.end_point with
    | Some _, Some k1 -> 0.0 <= k1 && k1 <= 1.0
    | _, _ -> false

  let%expect_test "collinear_overlap" =
    let open Float in
    [|
      (* vertical lines overlap *)
      collinear_overlap
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 0.0; y = -1.0 } }
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 0.0; y = -1.0 } };
      (* partially overlapping horizontal lines *)
      collinear_overlap
        { start_point = { x = -1.0; y = 0.0 }; end_point = { x = 1.0; y = 0.0 } }
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 2.0; y = 0.0 } };
      (* non-overlapping horizontal lines *)
      collinear_overlap
        { start_point = { x = -1.0; y = 0.0 }; end_point = { x = 1.0; y = 0.0 } }
        { start_point = { x = 2.0; y = 0.0 }; end_point = { x = 3.0; y = 0.0 } };
      (* two overlapping diagonal lines *)
      collinear_overlap
        {
          start_point = { x = -1.0 / sqrt 2.0; y = -1.0 / sqrt 2.0 };
          end_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
        }
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 1.0 } };
      (* two non-overlapping diagonal lines *)
      collinear_overlap
        {
          start_point = { x = -1.0 / sqrt 2.0; y = -1.0 / sqrt 2.0 };
          end_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
        }
        { start_point = { x = 1.0; y = 1.0 }; end_point = { x = 2.0; y = 2.0 } };
      (* two overlapping horizontal lines in which s0's endpoint does not lie on s1. *)
      collinear_overlap
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 2.0; y = 0.0 } }
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 0.0 } };
    |]
    |> printf !"%{sexp: bool array}";
    [%expect {| (true true false true false false) |}]

  (**
    Accepts two segments and returns 1 iff they intersect at points
    between their endpoints or they overlap and s0's endpoint lies
    on s1 somewhere between s1's endpoints, 0.5 if they intersect at one
    of their endpoints, and 0 if the do not intersect at all.

    Note: these numerical values were selected to simply counting the
    number of times that a line segment crosses the boundaries of a
    polygon.
  *)
  let intersect s0 s1 =
    let open Float in
    let d0x = s0.end_point.x - s0.start_point.x in
    let d0y = s0.end_point.y - s0.start_point.y in
    let d1x = s1.end_point.x - s1.start_point.x in
    let nd1y = s1.start_point.y - s1.end_point.y in
    let det = (d0x * nd1y) + (d0y * d1x) in
    if [%equal: float] det 0.0
    then
      (* if the determinant is 0 then the only way that the two segments can intersect is if they are collinear and s0's endpoint lies on s1. *)
      if collinear_overlap s0 s1 then 1.0 else 0.0
    else (
      let k0 =
        (((s1.start_point.x - s0.start_point.x) * nd1y) + (d1x * (s1.start_point.y - s0.start_point.y)))
        / det
      in
      let k1 =
        ((d0x * (s1.start_point.y - s0.start_point.y)) - (d0y * (s1.start_point.x - s0.start_point.x)))
        / det
      in
      (* check if intersects *)
      if 0.0 <= k0 && k0 <= 1.0 && 0.0 <= k1 && k1 <= 1.0
      then
        (* check if intersects at an endpoint *)
        if k0 = 0.0 || k0 = 1.0 || k1 = 0.0 || k1 = 1.0 then 0.5 else 1.0
      else 0.0)

  let%expect_test "intersect" =
    let open Float in
    [|
      (* two perpendicular lines through the origin *)
      intersect
        { start_point = { x = 1.0; y = 0.0 }; end_point = { x = -1.0; y = 0.0 } }
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 0.0; y = -1.0 } };
      (* two horizontal overlapping lines through the origin *)
      intersect
        { start_point = { x = 1.0; y = 0.0 }; end_point = { x = -1.0; y = 0.0 } }
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 0.0 } };
      (* two horizontal nonoverlapping lines *)
      intersect
        { start_point = { x = 1.0; y = 0.0 }; end_point = { x = -1.0; y = 0.0 } }
        { start_point = { x = 2.0; y = 0.0 }; end_point = { x = 3.0; y = 0.0 } };
      (* two diagonal lines crossing at a single midpoint. *)
      intersect
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 1.0 } }
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 1.0; y = 0.0 } };
      (* two diagonal lines that miss. *)
      intersect
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 1.0; y = 0.0 } }
        { start_point = { x = -1.0; y = 0.0 }; end_point = { x = 0.0; y = -1.0 } };
      (* two diagonal lines partially overlap. *)
      intersect
        {
          start_point = { x = -1.0 / sqrt 2.0; y = -1.0 / sqrt 2.0 };
          end_point = { x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
        }
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 1.0 } };
      (* a diagonal line and a horizontal line that intersect at one of their endpoints. *)
      intersect
        { start_point = { x = 0.0; y = 0.0 }; end_point = { x = 1.0; y = 1.0 } }
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 1.0; y = 1.0 } };
      intersect
        { start_point = { x = 1.0; y = 1.0 }; end_point = { x = 1.0; y = 0.0 } }
        { start_point = { x = -1.0; y = -1.0 }; end_point = { x = 1.5; y = 0.5 } };
      (* a diagonal line that does not reach a horizontal line but whose extension intersects its end point. *)
      intersect
        { start_point = { x = -1.0; y = -1.0 }; end_point = { x = 0.5; y = 0.5 } }
        { start_point = { x = 0.0; y = 1.0 }; end_point = { x = 1.0; y = 1.0 } };
    |]
    |> printf !"%{sexp: float array}";
    [%expect {| (1 0 0 1 0 1 0.5 1 0) |}]
end

(**
  Accepts a set of polygonal regions and a point and returns true iff
  the point is within one of the polygonal regions.

  Note: this function uses the boundary crossing counting method.
*)
(* let internal (shapes : Shape.Polygon.t) (p : point) : bool =
   let origin = Float.{ x = shapes.bbox.xmin - 1.0; y = shapes.bbox.ymin - 1.0 } in
   let s0 = Segment.{ start_point = origin; end_point = p } in
   Array.exists shapes.points ~f:(fun points ->
       let rec aux n = function
         | -1 -> Float.(n % 2.0 = 1.0)
         | i ->
           let start_point = { x = points.(i).x; y = points.(i).y } in
           (* return true if the point is a polygon vertex *)
           [%equal: point] p start_point
           ||
           let j = if i < Array.length points - 1 then i + 1 else 0 in
           let end_point = { x = points.(j).x; y = points.(j).y } in
           if [%equal: point] start_point end_point
           then (* skip this point of it is the same as the previous point. *)
             (aux [@tailcall]) n (pred i)
           else (
             let s1 = Segment.{ start_point; end_point = { x = points.(j).x; y = points.(j).y } } in
             (* return true if the point lies on an edge *)
             Option.is_some (Segment.collinear_point s1 p)
             (* continue counting the number of times the reference segment crosses a polygon edge. *)
             || (aux [@tailcall]) (n +. Segment.intersect s0 s1) (pred i))
       in
       aux 0.0 (Array.length points - 1)) *)

let internal (shapes : Shape.Polygon.t) (p : point) : bool =
  let origin = Float.{ x = shapes.bbox.xmin - 1.0; y = shapes.bbox.ymin - 1.0 } in
  let s0 = Segment.{ start_point = origin; end_point = p } in
  let n = ref 0.0 in
  Array.exists shapes.points ~f:(fun points ->
      n := 0.0;
      try
        for i = 0 to Array.length points - 1 do
          let start_point = { x = points.(i).x; y = points.(i).y } in
          (* true if the point is a corner *)
          if [%equal: point] p start_point then raise Exit;
          let j = if i < Array.length points - 1 then i + 1 else 0 in
          let end_point = { x = points.(j).x; y = points.(j).y } in
          (* skip this point of it is the same as the previous point. *)
          if not ([%equal: point] start_point end_point)
          then (
            let s1 = Segment.{ start_point; end_point } in
            (* true if the point is on the boundary *)
            if Option.is_some (Segment.collinear_point s1 p) then raise Exit;
            (* update count of boundaries crossed *)
            let d = Segment.intersect s0 s1 in
            n := !n +. d)
        done;
        (* printf !"number of segment intersections: %{sexp: float}\n" !n; *)
        [%equal: float] (!n %. 2.0) 1.0
      with
      | Exit -> true)

let%expect_test "internal" =
  [|
    (let shapes =
       Shape.Polygon.
         {
           bbox = { xmin = 0.0; xmax = 1.0; ymin = 0.0; ymax = 1.0 };
           points =
             [|
               [|
                 { x = 0.0; y = 0.0 }; { x = 0.0; y = 1.0 }; { x = 1.0; y = 1.0 }; { x = 1.0; y = 0.0 };
               |];
             |];
         }
     in
     [|
       internal shapes { x = 0.5; y = 0.5 };
       internal shapes { x = 0.0; y = 0.0 };
       internal shapes { x = 1.0; y = 0.0 };
       internal shapes { x = 1.0; y = 1.0 };
       internal shapes { x = 1.5; y = 0.5 };
       internal shapes { x = 1.5; y = 0.4 };
       internal shapes { x = 1.5; y = 0.6 };
     |]);
    (* a triangle in which the one side is aligned to the reference point. *)
    (let shapes =
       Shape.Polygon.
         {
           bbox = { xmin = -1.0; xmax = 1.0; ymin = 0.0; ymax = 2.0 };
           points = [| [| { x = 0.0; y = 0.0 }; { x = 1.0; y = 1.0 }; { x = 2.0; y = 0.0 } |] |];
         }
     in
     [|
       internal shapes { x = 1.0; y = 1.0 };
       internal shapes Float.{ x = 1.0 / sqrt 2.0; y = 1.0 / sqrt 2.0 };
       internal shapes { x = 1.0; y = 0.5 };
       internal shapes { x = 1.0; y = 0.0 };
       internal shapes { x = 1.5; y = 0.5 };
       internal shapes { x = 2.0; y = 0.5 };
     |]);
  |]
  |> printf !"%{sexp: bool array array}";
  [%expect {| ((true true true true false false false) (true true true true true false)) |}]
