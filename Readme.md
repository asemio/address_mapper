OCaml Maps
==========

This package defines a collection of tools that can be used to generate SVG maps derived from ESRI Shapefiles using OCaml.

The main output is a Docker image that contains an executable in /app/main.exe. This program takes ESRI Shapefiles and returns a map as an SVG image. The SVG file contains one polygon for each region and can be modified (i.e. colored) by other programs.

This package was originally created to generate SVG maps of census tracts in Tulsa Oklahoma. The Census Bureau provides ESRI Shapefiles that describe the boundaries of census tracts. The OCAML Maps program draws these census tracts on a map and we then modified these maps to create data visualizations.

If you are taking geographical regions described by ESRI Shapefiles and want to generate an SVG image that maps these regions, this package may be for you.
