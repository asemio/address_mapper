Address Mapper Readme
=====================

The Address Mapper package defines a program that can be used to map addresses onto geographical regions defined by ESRI Shapefiles. The program takes a set of ESRI Shapefiles, ESRI DBF Database files, and a CSV file that contains addresses, and maps those addresses to regions defined by the Shapefiles.

The Census Bureau publishes Shapefiles and DBF files that list street segments and the address ranges that lie along them. These files are typically named "addrfeat." This program uses these Shapefiles to determine where addresses are and then compares them with the region boundaries defined in other ESRI Shapefiles provided by the Census Bureau. The Shapefiles published by the Ceneus Bureau are all compatible in the sense that none of the street segments defined in an "addrfeat" file crosses any regional boundaries defined by the Bureau's other Shapefiles.

