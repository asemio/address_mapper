open! Core

module Address : sig
  type t = {
    house: string option;
    category: string option;
    near: string option;
    house_number: string option;
    road: string option;
    unit: string option;
    level: string option;
    staircase: string option;
    entrance: string option;
    po_box: string option;
    postcode: string option;
    suburb: string option;
    city_district: string option;
    city: string option;
    island: string option;
    state_district: string option;
    state: string option;
    country_region: string option;
    country: string option;
    world_region: string option;
  }
  [@@deriving sexp, equal, compare, hash, fields, to_yojson]

  val to_string : t -> string
end

val component : string -> Address.t -> string option

val code : string -> char

type ready =
  | Unknown
  | No
  | Later
  | Yes

val ready : ready ref

val setup : string -> unit -> unit Lwt.t

module AddressSet : sig
  include Set.S with type Elt.t := Address.t

  val hash : t -> int

  val hash_fold_t : Hash.state -> t -> Hash.state
end

val parse : string -> AddressSet.t
