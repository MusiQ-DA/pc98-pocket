# quartus-wine-slim — the Quartus Standard 18.1/Wine image minus everything a
# Cyclone-V headless compile never touches.
#
# The stock image carries the whole install: every Cyclone family's devinfo,
# the Platform Designer IP catalog, Nios II EDS, HLS, DSP Builder, simulation
# libraries, PDB debug symbols, a bundled Cygwin and JRE. This design compiles
# to one device (5CEBA4F23C8) from fully committed, pre-generated IP -- none of
# that is load-bearing for map/fit/asm/sta.
#
# COPY --from into scratch squashes the result into one layer, so the
# deletions actually shrink the image instead of whiteing out beneath it.
#
#   docker build --platform linux/amd64 -t quartus-wine:18.1-slim docker/quartus-wine-slim
FROM ghcr.io/musiq-da/quartus-wine:18.1 AS src

RUN rm -rf \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/bin64/pdbmin \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/bin64/cygwin \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/bin64/jre64 \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/common/devinfo/cycloneive \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/common/devinfo/cycloneivgx \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/eda \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/cusp \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/dspba \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/dsp_builder \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/sopc_builder \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/qdesigns \
    /opt/prefix/drive_c/intelFPGA/18.1/quartus/drivers \
    /opt/prefix/drive_c/intelFPGA/18.1/nios2eds \
    /opt/prefix/drive_c/intelFPGA/18.1/hls \
    /opt/prefix/drive_c/intelFPGA/18.1/ip \
    /opt/prefix/drive_c/intelFPGA/18.1/uninstall \
    /opt/prefix/drive_c/intelFPGA/18.1/logs

FROM scratch
COPY --from=src / /
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/opt/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEESYNC=1 \
    HOME=/home/hiroya
USER hiroya
WORKDIR /work
ENTRYPOINT ["wine"]
CMD ["C:\\intelFPGA\\18.1\\quartus\\bin64\\quartus_sh.exe", "--version"]
