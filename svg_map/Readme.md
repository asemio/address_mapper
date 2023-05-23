SVG Map Readme
==============

The SVG Map generator program takes an ESRI shapefile and returns an SVG image that plots the Shapefile regions.


Data Readme
-----------

These files were downloaded from the Census Bureau's website.

The simplifield Shapefile tl_2022_40_tract_simpl.shp was generated from the tl_2022_40_tract.shp Shapefile using https://mapshaper.org/. I simply imported the Shapefile, simplified the shapefile using the Simplify operator, and then re-exported it as a Shapefile.

We use this simplified shapefile to generate maps. The default shapefiles are used for location mapping, but are impractical for visualization because they include millions of points.

Compilation
-----------

This program uses OCaml's OPAM and Dune build systems to compile the program's source code and generate an executable. To compile the source code run:

```bash
opam switch create . 5.0.0+options --no-install
eval $(opam env)
opam update
opam install --deps-only . -y
dune build
```