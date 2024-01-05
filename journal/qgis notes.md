# QGIS Notes

## Introduction

QGIS is a free program that can be used to create static high resolution data maps.

## Adding a Base Layer to Your Maps

The base layer refers to the raster map image that you will overlay you map data on. QGIS comes with an Open Street Map base layer which is usually sufficient. To add this base layer to your project:

1. Create a new project by clicking the New Project file icon in the top icon menu bar.
2. In the left Browser pane click XYZ Tiles > Open Street Map

This will add the Open Street Map as a base layer.

## ESRI Shapefiles

A "Shapefile" is actually a collection of files bundled together. In the package is an actual "shapefile" ending with "shp." There's also a "projection" file, which ends in "prj." And, a database file that ends in "dbf." There are two other files included in these bundles, but I do not know what they are actually used for. They end in "shx" and "cpg" respectively.

## Adding Shapefiles to a Map

ESRI Shapefiles are used to define polygonal regions on a map. These regions may represent census tracts, zip code regions, school districts, and other areas. The Census Bureau, Tulsa Public Schools, and Tulsa Health Department all publish ESRI shapefiles that define these regions. QGIS can draw regions defined by shapefiles on your maps. To draw Shapefile regions on your map:

1. In the Top Menu, navigate to Layer > Add Layer > Add Vector Layer

2. In the Data Source Manager | Vector Window, select your shapefile (the file should end in "shp") from the Source field and press the Add button at the bottom of the window.

This will add a new layer to your project. You can find it in the Layers pane.

## Adding Data

Normally, we want to express data through our maps. We might want to label or colorize regions based on some numerical property. For example, we might want to show the number of people who live in a region, the average income of a region, etc. QGIS allows us to add data to a map. The simplest way to add data is to associate a CSV file with your map. You can then "link" the CSV file with a vector layer and change its labels and colors based on the values stored in the CSV file.

To add a CSV data file to a map:

1. In the Top Menu, navigate to Layer > Add Delimited Text Layer. This will open the Data Source Manager | Delimited Text window.
2. Set the Filename field to your CSV file.
3. Set the remaining fields as you see fit
4. In the bottom of the window you will see a sample of your data along with the data types that QGIS inferred for your data. Change these to be the correct data types (you cannot change them latter). Ensure that numerical data is correctly coded as such.
5. Click the Add button at the bottom of the window. This will add your data, but will not close the window. Click the Close button.

You will now see your data added as a new layer in the Layers pane.

## Creating a Stainglass Map

One of the most common visualizations we create are "stainglass" maps. These are just maps in which semitransparent polygonal regions are colored while overlying a base map. To create such a map:

1.  Add a shapefile defining your regions (see: "Adding Shapefiles to a Map")
2. Add data (see: "Adding Data")
3. link your data to your shapefile layer by double clicking on the shapefile layer. This will open the Layer Properties window. Click on the Joins icon (the blue funnel).
4. In the bottom of the Layer Properties: Join window click the Add icon (the green plus icon). This will open the Add Vector Join window.
5. Set the Join Layer to the data layer. Set the "Join field" field to the name of the column in the data file that you will use to specify which shapefile region a row applies to. Set the "Target field" field to the to the name of the Shapefile's DBF column that the data field has to match against. Set any other fields that are relevant and click the Ok button.
6. In the left pane of the Layer Properties window click on the Fields icon to open the Layer Properties: Fields window and review the fields now available. You should see your data fields.
7. In the left pane of the Layer Properties window click on the Feature Symbology icon to open the Layer Properties: Feature Symbology window. Here you can change the color of the shapefile regions based on the data values.
8. In the top dropdown field select "Graduated."
9. Click the formula icon next to the "Value" field. This will open the Expression Dialog. In the Middle Pane, expand the Fields and Values drop down. This will show the available field values. Select the column that you want to use to control the color of the region.
10. Set the remaining fields in the Symbology window and be sure to generate the scale by clicking the Classify button. Then press Ok.

## Shapefile Projections

There are different types of projections. Some of define a central reference point and describe other locations by measuring their distance from this central reference point. In 2023, Tulsa Public Schools provided us with a shapefile that used this type of coordinate system. Other coordinate systems use longitude and latitudes to specify locations. You can use QGIS to lookup information about different projection systems. The notes within QGIS's database will tell you whether or not the projection system uses longitude and latitudes or not. As a general rule, you should only use reference systems like GCS_NAD_1983_2011 that use longitude and latitude coordinates. My Address Mapper program expects shapefiles that have longitudinal and latitudinal coordinates.

## Fixing Shapefile Projections

You can use QGIS to change a Shapefiles' projection system. To do this:

1. Add the shapefile to your map (see instructions under "Adding Shapefiles to a Map")
2. Right click on the new layer to open the Layer menu. Select Export > Save Features As.
3. Keep the Format = ESRI Shapefile. Enter a new filename. Change CRS = GCS_NAD_1983_2011 or select some other projection that uses longitude and latitude. You can see information about the available projections by clicking on the world icon to the right of the CRS field. Uncheck the "Persist layer metadata" checkbox. Uncheck the "Add saved file to map" checkbox. And, click the Ok button.

This will create a new Shapefile using the selected projection.

## Saving your Maps as High Resolution Images

Project > Import/Export > Export Map to Image.