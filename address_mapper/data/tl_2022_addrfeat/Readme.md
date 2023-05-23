Composite Address Features File
===============================

This ESRI Shapefile directory lists all of the address ranges and street segments in Tulsa County and the counties that are immediately adjacent to it. I created it by concatenating together the following Census Bureau shapefiles:

| County | File |
| ------ | ---- |
| Owasso County | tl_2022_40113_addrfeat |
| Creek County | tl_2022_40037_addrfeat |
| Rogers County | tl_2022_40131_addrfeat |
| Wagoner County | tl_2022_40145_addrfeat |
| Okmulgee County| tl_2022_40111_addrfeat |
| Pawnee County | tl_2022_40117_addrfeat |
| Washington County | tl_2022_40147_addrfeat
| Muskogee County | tl_2022_40101_addrfeat |
| Tulsa County | tl_2022_40143_addrfeat |

I downloaded these Shapefiles from the Census Bureau website:

* https://www.census.gov/cgi-bin/geo/shapefiles/index.php?year=2022&layergroup=Relationship+Files

and used QGIS to merge them together.