OCaml Maps
==========

This package defines a collection of tools that can be used to generate SVG maps derived from ESRI Shapefiles using OCaml.

The main output is a Docker image that contains an executable in /app/main.exe. This program takes ESRI Shapefiles and returns a map as an SVG image. The SVG file contains one polygon for each region and can be modified (i.e. colored) by other programs.

This package was originally created to generate SVG maps of census tracts in Tulsa Oklahoma. The Census Bureau provides ESRI Shapefiles that describe the boundaries of census tracts. The OCAML Maps program draws these census tracts on a map and we then modified these maps to create data visualizations.

If you are taking geographical regions described by ESRI Shapefiles and want to generate an SVG image that maps these regions, this package may be for you.

Compilation
-----------

This program uses OCaml's OPAM and Dune build systems to compile the program's source code and generate an executable. To compile the source code run:

```bash
opam switch create . 5.0.0+options --no-install
opam update
opam install --deps-only .
dune build
```

Running the Program Locally
---------------------------

1. Download the ESRI Shapefiles and DBF files from the Census Bureau

You must download two sets of ESRI Shapefiles and DBF files from the [Census Bureau](https://www.census.gov/cgi-bin/geo/shapefiles/index.php?year=2022&layergroup=Census+Tracts). The first set should be the Address Features files for the region that you want to study. Then you must download the boundary Shapefiles. For example, if you want to use census tracts, you will need the census tract shapefiles. If you want to use school boundaries, you will need these files.

2. Download the Libpostal Data

This program uses [Libpostal](https://github.com/openvenues/libpostal) to parse addresses. Before you can run this program, you will need to download the Libpostal data. It should be stored in the libpostal folder as a subfolder called "libpostal_data".

3. Create the Input Data File

This program takes a CSV file that contains addresses and generates a new CSV file that includes the name of the region that the address belongs to. Create a file similar to that given in example_clients.csv.

4. Draft the Configuration File

Before you can run the program, you must create and configure the configuration file. The configuration file is a JSON file that tells the program what ESRI Shapefiles and DBF files to use to map addresses and to define regions. The example_config.json file illustrates the format.

5. Run the Program

```
dune exec src/main.exe CONFIG_FILE
```

This will create a new CSV file that includes region IDs for each address that the program was able to geolocate.

Note: this program will generate a cache file called "segments_map.bin" by default. You can resuse this file to speed up subsequent runs. Note however, that this file should only be used when processing addresses in the same region and with the same boundaries.

Generating the Docker Image
---------------------------

Run `docker build . -t "address_mapper"` to build the Docker image.

Deploying the Docker Image
--------------------------

Running the Program within Docker
---------------------------------