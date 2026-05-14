FROM mcr.microsoft.com/oss/mirror/docker.io/library/ubuntu:20.04
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y install wget build-essential swig cmake git libnuma-dev python3.8-dev python3-distutils gcc-8 g++-8 \
    libboost-filesystem-dev libboost-test-dev libboost-serialization-dev libboost-regex-dev libboost-serialization-dev libboost-regex-dev libboost-thread-dev libboost-system-dev libtbb-dev \
    libssl-dev libyaml-dev zlib1g-dev

RUN wget https://bootstrap.pypa.io/pip/3.8/get-pip.py && python3.8 get-pip.py && python3.8 -m pip install numpy

# Aerospike C client (for optional -DAEROSPIKE=ON image builds)
RUN cd /tmp && \
    wget -q https://download.aerospike.com/artifacts/aerospike-client-c/7.3.0/aerospike-client-c_7.3.0_ubuntu20.04_x86_64.tgz && \
    tar -xzf aerospike-client-c_7.3.0_ubuntu20.04_x86_64.tgz && \
    cd aerospike-client-c_7.3.0_ubuntu20.04_x86_64 && \
    dpkg -i *.deb && \
    apt-get -f -y install && \
    rm -rf /tmp/aerospike-client-c_7.3.0_ubuntu20.04_x86_64*

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
