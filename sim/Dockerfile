# Simulation image for the SDRAM controller work.
# Built locally; the host's DNS is broken but Docker Desktop resolves for
# containers, so apt works in here even when it does not outside.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      verilator make g++ perl python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
