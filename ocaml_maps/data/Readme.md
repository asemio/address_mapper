Data Readme
===========

These files were downloaded from the Census Bureau's website.

The simplifield Shapefile tl_2022_40_tract_simpl.shp was generated from the tl_2022_40_tract.shp Shapefile using https://mapshaper.org/. I simply imported the Shapefile, simplified the shapefile using the Simplify operator, and then re-exported it as a Shapefile.

We use this simplified shapefile to generate maps. The default shapefiles are used for location mapping, but are impractical for visualization because they include millions of points.