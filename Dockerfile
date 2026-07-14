FROM mcr.microsoft.com/oss/mirror/docker.io/library/ubuntu:20.04
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y install wget build-essential swig cmake git pkg-config libnuma-dev python3.8-dev python3-distutils gcc-8 g++-8 \
    libboost-filesystem-dev libboost-test-dev libboost-serialization-dev libboost-regex-dev libboost-serialization-dev libboost-regex-dev libboost-thread-dev libboost-system-dev libtbb-dev \
    libssl-dev libyaml-dev zlib1g-dev

RUN wget https://bootstrap.pypa.io/pip/3.8/get-pip.py && python3.8 get-pip.py && python3.8 -m pip install numpy

# EC528 forked Aerospike C client, built from source (VECTOR_DISTANCE wire
# support; master commit 9ae3eda3+). The stock aerospike.com client tarball
# lacks aerospike_vector_distance.h and only ships x86_64 - do not reintroduce
# it. Full (non-shallow) clone: submodule pins need not be branch tips.
RUN cd /tmp && \
    git clone --recursive -b ec528/modules-abs-path https://github.com/dzokha-true/aerospike-client-c.git && \
    cd aerospike-client-c && \
    make && \
    TARGET_DIR=$(ls -d target/Linux-*) && \
    cp -a "$TARGET_DIR/include/." /usr/local/include/ && \
    cp -a "$TARGET_DIR/lib/." /usr/local/lib/ && \
    ldconfig && \
    test -f /usr/local/include/aerospike/aerospike_vector_distance.h && \
    cd /tmp && rm -rf aerospike-client-c

ENV PYTHONPATH=/app/Release

COPY CMakeLists.txt ./
COPY AnnService ./AnnService/
COPY Test ./Test/
COPY Wrappers ./Wrappers/
COPY GPUSupport ./GPUSupport/
COPY ThirdParty ./ThirdParty/

RUN export CC=/usr/bin/gcc-8 && export CXX=/usr/bin/g++-8 && mkdir build && cd build && \
    AS_INC=$(find /usr /opt -path '*/aerospike/aerospike.h' 2>/dev/null | head -n 1 | sed 's|/aerospike/aerospike.h||') && \
    AS_LIB=$(find /usr /opt -name 'libaerospike.so' 2>/dev/null | head -n 1) && \
    if [ -z "$AS_LIB" ]; then AS_LIB=$(find /usr /opt -name 'libaerospike.a' 2>/dev/null | head -n 1); fi && \
    echo "Aerospike include: $AS_INC" && echo "Aerospike library: $AS_LIB" && \
    cmake -DCMAKE_BUILD_TYPE=Release .. \
        -DAEROSPIKE=ON \
        -DAEROSPIKE_INCLUDE_DIR="$AS_INC" \
        -DAEROSPIKE_CLIENT_LIBRARY="$AS_LIB" && \
    make -j$(nproc) && cd ..

# EC528: the offload build is only real if the VECTOR_DISTANCE probe passed.
# Fail the image build loudly otherwise; write the marker only on success.
RUN if grep -q '^SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE:INTERNAL=1$' /app/build/CMakeCache.txt; then \
        echo 'SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE=1' > /app/build/offload_probe_ok; \
    else \
        echo 'FATAL: aerospike_vector_distance.h probe failed - offload build is not real' >&2; \
        grep -n 'SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE' /app/build/CMakeCache.txt >&2 || true; \
        exit 1; \
    fi

COPY Script_AE/run-offload-tests.sh /app/run-offload-tests.sh
RUN chmod +x /app/run-offload-tests.sh
