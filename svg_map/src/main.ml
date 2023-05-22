open! Core
open! Lwt.Syntax
open! Lwt.Infix
open! Lib.Aux
open! Lib

module Command_line = struct
  type t = {
    config_file_path: string;
    verbose: bool;
  }
end

module Config = struct
  (* represents the configuration file *)
  type t = {
    census_tract_dbf_file: string;
    census_tract_dbf_file_name_column: string;
    census_tract_simplified_shp_file: string;
    census_tract_map_base_layer_file: string;
    census_tract_map_file: string;
    census_tract_map_bbox: Shape.BBox.t;
  }
  [@@deriving of_yojson]
end

let read_config_file filename =
  let+ content = Aux.read_file ~filename in
  content |> Yojson.Safe.from_string |> Config.of_yojson |> Result.ok_or_failwith

let create_census_tract_svg (config : Config.t) =
  let attribs =
    Asemio_dbf.read config.census_tract_dbf_file
    |> Census_tract.Dbf.get config.census_tract_dbf_file_name_column
  in
  let _header, shapes = Census_tract.Shape.read config.census_tract_simplified_shp_file in
  Census_tract.get attribs shapes
  |> Array.filter ~f:(fun tract -> Shape.BBox.overlaps config.census_tract_map_bbox tract.bbox)
  |> Census_tract.tracts_to_svg ~width:500 ~height:500
       ~get_id:(fun _i tract -> sprintf "%s" tract.name)
       config.census_tract_map_bbox config.census_tract_map_base_layer_file
  |> Aux.write_to_file ~filename:config.census_tract_map_file

let main Command_line.{ config_file_path; verbose } =
  Aux.verbose := verbose;
  let* config = read_config_file config_file_path in
  create_census_tract_svg config

let () =
  let open Command in
  let open Command.Let_syntax in
  let global_options =
    let%map config_file_path = Param.("config_file_path" %: string |> anon)
    and verbose =
      Param.(
        flag "--verbose" ~full_flag_required:() no_arg
          ~doc:"Instructs this utility to print periodic progress updates.")
    in
    Command_line.{ config_file_path; verbose }
  in
  global_options
  >>| (fun options () -> Lwt_main.run (main options))
  |> basic
       ~summary:"Takes a Shapefile and creates an SVG file that can be used to create stain glass maps using the shapefile regions."
  |> Command_unix.run ~version:"1.0"
