# Run: `docker build . -t "address_mapper"`
# then: `docker run -it --rm "address_mapper"`
# on terminal run: eval $(opam env)
# and then: dune exec src/main.exe
FROM ubuntu:20.04 AS build_shared

WORKDIR /home

RUN apt update \
  && apt upgrade -y \
  && DEBIAN_FRONTEND=noninteractive apt-get -y install tzdata \
  && apt install -y pkg-config build-essential libffi-dev autoconf libtool curl

#  -------------------- #
FROM build_shared AS build_libpostal

COPY libpostal libpostal
RUN cd libpostal \
  && ./configure --datadir="$(pwd)/libpostal_data" \
  && ./bootstrap.sh \
  && make -j4 install

#  -------------------- #
FROM build_shared AS build

WORKDIR /home/address_mapper

RUN apt install -y opam libev-dev libgsl-dev \
  && opam init --yes --disable-sandboxing \
  && opam switch create . 5.0.0+options --no-install \
  && opam update

COPY address_mapper_linux_opam address_mapper.opam
RUN opam install --deps-only -y .

COPY src src
COPY dune .
COPY dune-project .

RUN cd src/lib/postal \
  && rm -f dune \
  && ln linux.dune dune

COPY --from=build_libpostal /usr/local/include/libpostal libpostal/src
COPY --from=build_libpostal /usr/local/lib/libpostal.so.1.0.1 /usr/local/lib/libpostal.so

RUN eval $(opam env) && dune build

#  -------------------- #
FROM ubuntu:20.04

RUN apt update \
  && apt upgrade -y \
  && apt install -y libgsl-dev libev-dev vim

WORKDIR /app
COPY --from=build /home/address_mapper/_build/default/src/main.exe .
# COPY --from=build_libpostal /home/libpostal/libpostal_data libpostal/libpostal_data
COPY --from=build_libpostal /usr/local/lib/libpostal.so.1.0.1 /usr/local/lib/libpostal.so
COPY --from=build_libpostal /usr/local/lib/libpostal.so.1.0.1 /usr/local/lib/libpostal.so.1
COPY data data
COPY segments_map.bin .
COPY example_config.json .
COPY example_clients.csv .
