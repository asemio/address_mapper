Address Mapper Readme
=====================

The Address Mapper package defines a program that can be used to map addresses onto geographical regions defined by ESRI Shapefiles. The program takes a set of ESRI Shapefiles, ESRI DBF Database files, and a CSV file that contains addresses, and maps those addresses to regions defined by the Shapefiles.

The Census Bureau publishes Shapefiles and DBF files that list street segments and the address ranges that lie along them. These files are typically named "addrfeat." This program uses these Shapefiles to determine where addresses are and then compares them with the region boundaries defined in other ESRI Shapefiles provided by the Census Bureau. The Shapefiles published by the Ceneus Bureau are all compatible in the sense that none of the street segments defined in an "addrfeat" file crosses any regional boundaries defined by the Bureau's other Shapefiles.

Compilation
-----------

This program uses OCaml's OPAM and Dune build systems to compile the program's source code and generate an executable. To compile the source code run:

```bash
# generate libpostal data and install necessary libraries
cd address_mapper/libpostal
./bootstrap.sh
./configure --datadir=$(pwd)/libpostal_data
make -j4
sudo make install
# compile the address mapper library
cd ..
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

```bash
dune exec src/main.exe CONFIG_FILE
```

This will create a new CSV file that includes region IDs for each address that the program was able to geolocate.

Note: this program will generate a cache file called "segments_map.bin" by default. You can resuse this file to speed up subsequent runs. Note however, that this file should only be used when processing addresses in the same region and with the same boundaries.

Generating the Docker Image
---------------------------

Run `docker build . -t "llee454/address_mapper"` from address_mapper/ to build the Docker image.

Deploying the Docker Image
--------------------------

I maintain a Docker image for this project on [Docker Hub](https://hub.docker.com/repository/docker/llee454/address_mapper/general).

Run `docker push llee454/address_mapper:latest` to deploy it.

Running the Program within Docker
---------------------------------

To run the program, you will need to start a docker container with the image and mount the libpostal data directory.

```bash
docker run -it -v $(pwd)/libpostal/:/app/libpostal "llee454/address_mapper"
```