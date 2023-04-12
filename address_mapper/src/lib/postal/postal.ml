open! Core
open Lwt.Syntax

module Address = struct
  type t = {
    house: string option; [@sexp.option] [@yojson.default None]
    category: string option; [@sexp.option] [@yojson.default None]
    near: string option; [@sexp.option] [@yojson.default None]
    house_number: string option; [@sexp.option] [@yojson.default None]
    road: string option; [@sexp.option] [@yojson.default None]
    unit: string option; [@sexp.option] [@yojson.default None]
    level: string option; [@sexp.option] [@yojson.default None]
    staircase: string option; [@sexp.option] [@yojson.default None]
    entrance: string option; [@sexp.option] [@yojson.default None]
    po_box: string option; [@sexp.option] [@yojson.default None]
    postcode: string option; [@sexp.option] [@yojson.default None]
    suburb: string option; [@sexp.option] [@yojson.default None]
    city_district: string option; [@sexp.option] [@yojson.default None]
    city: string option; [@sexp.option] [@yojson.default None]
    island: string option; [@sexp.option] [@yojson.default None]
    state_district: string option; [@sexp.option] [@yojson.default None]
    state: string option; [@sexp.option] [@yojson.default None]
    country_region: string option; [@sexp.option] [@yojson.default None]
    country: string option; [@sexp.option] [@yojson.default None]
    world_region: string option; [@sexp.option] [@yojson.default None]
  }
  [@@deriving sexp, equal, compare, hash, fields, to_yojson]

  let to_string addr =
    let queue = Queue.create ~capacity:20 () in
    let conv name f =
      Option.iter (Field.get f addr) ~f:(fun x -> sprintf "%s: %s" name x |> Queue.enqueue queue)
    in
    Fields.iter ~house:(conv "House") ~category:(conv "Category") ~near:(conv "Near")
      ~house_number:(conv "House Number") ~road:(conv "Road") ~unit:(conv "Unit") ~level:(conv "Level")
      ~staircase:(conv "Staircase") ~entrance:(conv "Entrance") ~po_box:(conv "PO Bbox")
      ~postcode:(conv "Postcode") ~suburb:(conv "Suburb") ~city_district:(conv "City District")
      ~city:(conv "City") ~island:(conv "Island") ~state_district:(conv "State District")
      ~state:(conv "State") ~country_region:(conv "Country Region") ~country:(conv "Country")
      ~world_region:(conv "World Region");
    Queue.to_array queue |> String.concat_array ~sep:", "
end

let component = function
| "house" -> Address.house
| "category" -> Address.category
| "near" -> Address.near
| "house_number" -> Address.house_number
| "road" -> Address.road
| "unit" -> Address.unit
| "level" -> Address.level
| "staircase" -> Address.staircase
| "entrance" -> Address.entrance
| "po_box" -> Address.po_box
| "postcode" -> Address.postcode
| "suburb" -> Address.suburb
| "city_district" -> Address.city_district
| "city" -> Address.city
| "island" -> Address.island
| "state_district" -> Address.state_district
| "state" -> Address.state
| "country_region" -> Address.country_region
| "country" -> Address.country
| "world_region" -> Address.world_region
| s -> failwithf "Invalid address component '%s'. Please report this bug." s ()

let code = function
| "house" -> 'B'
| "category" -> 'K'
| "near" -> 'X'
| "house_number" -> 'N'
| "road" -> 'R'
| "unit" -> 'U'
| "level" -> 'F'
| "staircase" -> 'T'
| "entrance" -> 'E'
| "po_box" -> 'B'
| "postcode" -> 'P'
| "suburb" -> 'V'
| "city_district" -> 'Z'
| "city" -> 'C'
| "island" -> 'I'
| "state_district" -> 'D'
| "state" -> 'S'
| "country_region" -> 'A'
| "country" -> 'E'
| "world_region" -> 'W'
| s -> failwithf "Invalid address component code '%s'. Please report this bug." s ()

external stub_postal_setup : string -> (unit, string) Result.t = "stub_postal_setup"

external stub_postal_parse : string -> (string * string array) array = "stub_postal_parse"

type ready =
  | Unknown
  | No
  | Later
  | Yes
[@@deriving sexp, equal]

let ready = ref Unknown

let address_dir_exists data_dir = Lwt_unix.file_exists (sprintf "%s/data_version" data_dir)

let load_address_data data_dir =
  let* exists = address_dir_exists data_dir in
  if not exists
  then failwith "Address data directory does not exist. Did you forget to run `./download_addresses.sh`?";
  let* () = Lwt_io.printl "🏘️  Loading Address data..." in
  let* setup = Lwt_preemptive.detach (fun () -> stub_postal_setup data_dir) () in
  let* () = Lwt_io.printl "✅ Address data loaded." in
  let+ () = Lwt_io.flush Lwt_io.stdout in
  match setup with
  | Ok () ->
    ready := Yes;
    ()
  | Error msg -> failwith msg

let setup data_dir =
  match !ready with
  | Yes
   |Later
   |No ->
    (fun () -> Lwt.return_unit)
  | Unknown ->
    ready := Later;
    (fun () -> load_address_data data_dir)

module AddressSet = struct
  include Set.Make (Address)
  include Provide_hash (Address)
end

let parse address =
  if not (equal_ready !ready Yes)
  then failwith "Address support is not initialized. Please report this bug.";
  let components = stub_postal_parse address in

  Array.fold components ~init:String.Map.empty ~f:(fun acc (label, values) ->
      let left = String.Set.of_array values in
      String.Map.update acc label ~f:(function
        | None -> left
        | Some right -> String.Set.union left right))
  |> String.Map.fold ~init:[ [] ] ~f:(fun ~key:label ~data:values combinations ->
         List.fold combinations ~init:[] ~f:(fun new_combinations combination ->
             String.Set.fold values ~init:new_combinations ~f:(fun acc value ->
                 (Sexp.List [ Sexp.Atom label; Sexp.Atom value ] :: combination) :: acc)))
  |> List.fold ~init:AddressSet.empty ~f:(fun acc x ->
         let data = Sexp.List x |> Address.t_of_sexp in
         AddressSet.add acc data)
