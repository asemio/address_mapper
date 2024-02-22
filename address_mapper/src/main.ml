open! Core
open! Lwt.Syntax
open! Lwt.Infix
open! Lib.Aux
open! Lib

(**
  The depth of the lookup table used to search for census tracts.

  Note: a depth of 10 appears to be optimal empirically. Increasing
  the depth reduces the average number of census tracts to search
  through but increases the average number of levels to iterate
  through.
*)
let tract_lookup_table_depth = 10

(** Instructs this utility to report its progress every n records. *)
let progress_report_interval = 100

module Command_line = struct
  type t = {
    config_file_path: string;
    verbose: bool;
  }
end

module Config = struct
  (* represents the configuration file *)
  type t = {
    output_column: string;
    address_columns: string list;
    zip_column: string option; [@default None]
    libpostal_data_dir: string;
    census_tract_dbf_file: string;
    census_tract_dbf_file_name_column: string;
    census_tract_shp_file: string;
    census_addrfeat_dbf_file: string;
    census_addrfeat_shp_file: string;
    input_file: string;
    output_file: string;
    segment_map_file: string;
  }
  [@@deriving of_yojson]
end

let read_config_file filename =
  let+ content = Aux.read_file ~filename in
  content |> Yojson.Safe.from_string |> Config.of_yojson |> Result.ok_or_failwith

let get_address_column_indices ~column_names headers =
  List.filter_map column_names ~f:(fun address_column ->
      List.findi headers ~f:(fun _ header -> [%equal: string] header address_column) |> function
      | None ->
        failwiths ~here:[%here]
          "Error: Invalid configuration file. One of the named headers does not exist." address_column
          [%sexp_of: string]
      | Some (index, _) -> Some index)

(**
  WARNING: if you change this program's record structures and then
  call Marshal.from_string, this program will crash (potentially
  segfault).
*)
let read_road_segment_table_file (config : Config.t) =
  let+ contents = Aux.read_file ~filename:config.segment_map_file in
  let (keys, data) : string array * Address_features.t list array = Marshal.from_string contents 0 in
  let road_segments_map = String.Table.create ~size:(Array.length keys * 2) () in
  Array.iter2_exn keys data ~f:(fun key data -> Hashtbl.add_exn road_segments_map ~key ~data);
  road_segments_map

let write_road_segment_table_file (config : Config.t) road_segments_map =
  let key_queue = Queue.create ~capacity:(Hashtbl.length road_segments_map) () in
  let data_queue = Queue.create ~capacity:(Hashtbl.length road_segments_map) () in
  Hashtbl.iteri road_segments_map ~f:(fun ~key ~data ->
      Queue.enqueue key_queue key;
      Queue.enqueue data_queue data);
  let data = Queue.to_array key_queue, Queue.to_array data_queue in
  Marshal.to_string data [] |> Aux.write_to_file ~filename:config.segment_map_file

let create_census_tract_lookup_tree (config : Config.t) =
  let attribs =
    Asemio_dbf.read config.census_tract_dbf_file
    |> Census_tract.Dbf.get config.census_tract_dbf_file_name_column
  in
  let header, shapes = Census_tract.Shape.read config.census_tract_shp_file in
  Census_tract.get attribs shapes |> Census_tract.Lookup.get_lookup_table tract_lookup_table_depth header

let create_road_segments_map (config : Config.t) tracts =
  let attribs = Asemio_dbf.read config.census_addrfeat_dbf_file |> Address_features.Dbf.get in
  let _header, shapes = Shape.read config.census_addrfeat_shp_file |> Tuple2.map_snd ~f:Array.of_list in
  verbose_print "Indexing the street segments given in the Address Features files.\n";
  Address_features.get (Address_features.create_workspace ()) tracts attribs shapes

let get_road_segments_map (config : Config.t) =
  Lwt_unix.file_exists config.segment_map_file >>= function
  | true -> read_road_segment_table_file config
  | false ->
    let tracts = create_census_tract_lookup_tree config in
    let road_segments = create_road_segments_map config tracts in
    let road_segments_map = Address_features.get_segment_map road_segments in
    let+ () = write_road_segment_table_file config road_segments_map in
    road_segments_map

let process_data_file (config : Config.t) headers zip_column_index address_column_indices
   road_segments_map stream =
  let* oc = Lwt_io.open_file ~flags:overwrite_flags ~mode:Output config.output_file in
  let csv_output_channel = Csv_lwt.to_channel oc in
  let* () = Csv_lwt.output_record csv_output_channel (headers @ [ config.output_column ]) in
  let* num_rows =
    Lwt_stream.fold_s
      (fun row i ->
        if i % progress_report_interval = 0 then verbose_print @@ sprintf "processing row %d\n" i;
        let address = List.map address_column_indices ~f:(List.nth_exn row) |> String.concat ~sep:" " in
        let zip = Option.map zip_column_index ~f:(List.nth_exn row) in
        let census_tracts =
          Address_features.get_segment_tract road_segments_map ?zip address
          |> String.Set.map ~f:Census_tract.name
          |> Set.to_list
          |> [%to_yojson: string list]
          |> sprintf !"%{Yojson.Safe}"
        in
        let+ () = row @ [ census_tracts ] |> Csv_lwt.output_record csv_output_channel in
        succ i)
      stream 0
  in
  verbose_print @@ sprintf "Finished processing %d records\n" num_rows;
  Csv_lwt.close_out csv_output_channel

let main Command_line.{ config_file_path; verbose } =
  Aux.verbose := verbose;
  let* config = read_config_file config_file_path in
  let* headers, stream = get_csv_stream config.input_file in
  let address_column_indices = get_address_column_indices ~column_names:config.address_columns headers in
  let zip_column_index =
    match config.zip_column with
    | None -> None
    | Some zip_column -> (
      List.findi headers ~f:(fun _ -> [%equal: string] zip_column) |> function
      | None ->
        failwiths ~here:[%here]
          "Error: none of the headers in the CSV file match the given zip column name " zip_column
          [%sexp_of: string]
      | Some (zip_column_index, _) -> Some zip_column_index)
  in
  let* () = Postal.setup config.libpostal_data_dir () in
  let* road_segments_map = get_road_segments_map config in
  process_data_file config headers zip_column_index address_column_indices road_segments_map stream

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
       ~summary:
         "Accepts a CSV file containing addresses and adds a column that reports the census tract that \
          contains each address."
  |> Command_unix.run ~version:"2.0"
