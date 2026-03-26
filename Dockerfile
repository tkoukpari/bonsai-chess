## Render deployment for BonsaiChess (OCaml)
##
## Builds the native OCaml server with Dune, then runs it.
## The server serves static assets from `./web/` (see `lib/server.ml`).

FROM ocaml/opam:debian-12-ocaml-5.4

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    m4 \
    libpq-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

## Install dependencies + build
COPY . /app

RUN opam init -y --disable-sandboxing && opam update
## Uses `bonsai_chess.opam` (added in this repo) for dependency resolution.
RUN opam install -y . --deps-only
RUN opam exec -- dune build --profile release web/app.js
RUN opam exec -- dune build bin/main.exe

## Runtime
EXPOSE 8080
CMD ["opam", "exec", "--", "dune", "exec", "bin/main.exe"]

