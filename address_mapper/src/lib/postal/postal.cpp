#include <regex>
#include <map>
#include <string>

#include <caml/memory.h>
#include <caml/alloc.h>

#include "libpostal/src/libpostal.h"

using namespace std;

value v_error_of_string(value v_ret, value v_field, const string& error)
{
  CAMLparam2(v_ret, v_field);
  v_field = caml_alloc_initialized_string(error.length(), error.c_str());
  // Size 1, tag 1 (Error)
  v_ret = caml_alloc_small(1, 1);
  Field(v_ret, 0) = v_field;
  CAMLreturn (v_ret);
}

value v_ok_of_unit(value v_ret)
{
  CAMLparam1(v_ret);
  // Size 1, tag 0 (Ok)
  v_ret = caml_alloc_small(1, 0);
  Field(v_ret, 0) = Val_unit;
  CAMLreturn (v_ret);
}

extern "C"
value stub_postal_setup(value v_dir)
{
  CAMLparam1(v_dir);
  CAMLlocal2(v_ret, v_field);
  string dir { String_val(v_dir), caml_string_length(v_dir) };
  char *c_dir { dir.data() };

  caml_enter_blocking_section();

  bool failure { !libpostal_setup_datadir(c_dir) || !libpostal_setup_parser_datadir(c_dir) || !libpostal_setup_language_classifier_datadir(c_dir) };

  caml_leave_blocking_section();

  if (failure) {
    CAMLreturn (v_error_of_string(v_ret, v_field, string { "libpostal setup failed in stub" }));
  }

  CAMLreturn (v_ok_of_unit(v_ret));
}

const map<string, uint16_t> norm_options_by_label {
  { "house", LIBPOSTAL_ADDRESS_ANY },
  { "category", LIBPOSTAL_ADDRESS_CATEGORY },
  { "near", LIBPOSTAL_ADDRESS_NEAR },
  { "house_number", LIBPOSTAL_ADDRESS_HOUSE_NUMBER },
  { "road", LIBPOSTAL_ADDRESS_TOPONYM },
  { "unit", LIBPOSTAL_ADDRESS_UNIT },
  { "level", LIBPOSTAL_ADDRESS_LEVEL },
  { "staircase", LIBPOSTAL_ADDRESS_STAIRCASE },
  { "entrance", LIBPOSTAL_ADDRESS_ENTRANCE },
  { "po_box", LIBPOSTAL_ADDRESS_PO_BOX },
  { "postcode", LIBPOSTAL_ADDRESS_POSTAL_CODE },
  { "suburb", LIBPOSTAL_ADDRESS_ANY },
  { "city_district", LIBPOSTAL_ADDRESS_NAME },
  { "city", LIBPOSTAL_ADDRESS_NAME },
  { "island", LIBPOSTAL_ADDRESS_NAME },
  { "state_district", LIBPOSTAL_ADDRESS_NAME },
  { "state", LIBPOSTAL_ADDRESS_NAME },
  { "country_region", LIBPOSTAL_ADDRESS_NAME },
  { "country", LIBPOSTAL_ADDRESS_NAME },
  { "world_region", LIBPOSTAL_ADDRESS_NAME }
};

extern "C"
value stub_postal_parse(value v_address)
{
  CAMLparam1(v_address);
  string raw { String_val(v_address), caml_string_length(v_address) };
  CAMLlocal4(v_arr, v_key, v_values, v_data);

  caml_enter_blocking_section();

  // Manual normalizations
  string address { regex_replace(raw, regex("#"), " Apt ") };

  // Parse
  libpostal_address_parser_options_t parse_options { libpostal_get_address_parser_default_options() };
  libpostal_address_parser_response_t* parsed { libpostal_parse_address(address.data(), parse_options) };

  size_t num_pairs { parsed->num_components };
  vector<pair<string, vector<string>>> pairs {};
  pairs.reserve(num_pairs);

  for (size_t i { 0 }; i < num_pairs; i++) {
    string key { parsed->labels[i] };
    char* value { parsed->components[i] };

    // Normalize each component pair
    libpostal_normalize_options_t norm_options { libpostal_get_default_options() };
    uint16_t label_option { norm_options_by_label.at(key) };
    if (label_option) {
      norm_options.address_components = label_option;
    }
    norm_options.replace_numeric_hyphens = true;
    norm_options.delete_numeric_hyphens = true;

    size_t num_expansions {};
    char **expansions { libpostal_expand_address_root(value, norm_options, &num_expansions) };

    vector<string> values {};
    values.reserve(num_expansions);
    for (size_t i { 0 }; i < num_expansions; i++) {
      values.push_back(string { expansions[i] });
    }

    pairs.push_back(pair { key, values });

    libpostal_expansion_array_destroy(expansions, num_expansions);
  }
  libpostal_address_parser_response_destroy(parsed);

  // Load
  caml_leave_blocking_section();

  v_arr = caml_alloc(num_pairs, 0);
  int arr_field { 0 };
  for (const pair<string, vector<string>>& pair : pairs) {
    const string& key { pair.first };
    const vector<string>& values { pair.second };
    v_key = caml_alloc_initialized_string(key.length(), key.c_str());

    v_values = caml_alloc(values.size(), 0);

    int nested_field { 0 };
    for (const string& data : values) {
      v_data = caml_alloc_initialized_string(data.length(), data.c_str());
      Store_field(v_values, nested_field++, v_data);
    }

    v_data = caml_alloc_small(2, 0);
    Field(v_data, 0) = v_key;
    Field(v_data, 1) = v_values;

    Store_field(v_arr, arr_field++, v_data);
  }

  CAMLreturn (v_arr);
}
