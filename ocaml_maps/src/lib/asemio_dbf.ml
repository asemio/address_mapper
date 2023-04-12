open! Core
include Dbf

type file_type = Dbf.file_type =
  | FoxBASE
  | FoxBASE_plus_Dbase_III_plus_no_memo
  | Visual_FoxPro
  | Visual_FoxPro_autoincrement_enabled
  | Visual_FoxPro_with_field_type_Varchar_or_Varbinary
  | DBASE_IV_SQL_table_files_no_memo
  | DBASE_IV_SQL_system_files_no_memo
  | FoxBASE_plus_dBASE_III_PLUS_with_memo
  | DBASE_IV_with_memo
  | DBASE_IV_SQL_table_files_with_memo
  | FoxPro_2_x_or_earlier_with_memo
  | HiPer_Six_format_with_SMT_memo_file
[@@deriving sexp]

type date = int * int * int [@@deriving sexp]

type field_type = Dbf.field_type =
  | Character
  | Currency
  | Numeric
  | Float
  | Date
  | DateTime
  | Double
  | Integer
  | Logical
  | Memo
  | General
  | Picture
  | Autoincrement
  | Double_level7
  | Timestamp
  | Varchar
[@@deriving sexp]

type field = Dbf.field = {
  field_name: string;
  field_type: field_type;
  field_length: int;
  field_decimal_count: int;
  field_system_column: bool;
  field_column_can_store_null: bool;
  field_binary_column: bool;
  field_column_autoincrementing: bool;
}
[@@deriving sexp]

type header = Dbf.header = {
  file_type: file_type;
  last_update: date;
  fields: field list;
  nrecords: int;
  len_header: int;
  len_record: int;
}
[@@deriving sexp]

module Column = struct
  type t = Dbf.column =
    | String_data of string array
    | Float_data of float array
  [@@deriving sexp]
end

let get_string = function
| String_data data -> data
| x -> failwiths ~here:[%here] "Invalid column data type. String data expected." x [%sexp_of: Column.t]

let get_float = function
| Float_data data -> data
| x -> failwiths ~here:[%here] "Invalid column data type. Float data expected." x [%sexp_of: Column.t]

let int_of_string = function
| "" -> None
| s -> (
  try Some (Int.of_string s) with
  (* some house numbers have hyphens. These are a small minority of addresses and we simply discard them. *)
  | _ -> None)

type t = Dbf.t = {
  header: header;
  columns: (string * Column.t) list;
}
[@@deriving sexp]

let read filename =
  of_file filename |> function
  | Ok data -> data
  | _ -> failwiths ~here:[%here] "Parse error in DB" filename [%sexp_of: string]
