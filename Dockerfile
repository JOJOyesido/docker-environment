# syntax=docker/dockerfile:1

############################################################
# Stage 1: base
# Requirement 1 + Requirement 2
# Minimal Ubuntu 26.04 + timezone + non-root user
############################################################

FROM ubuntu:26.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=aoc
ARG USER_UID=10001
ARG USER_GID=10001

ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV TZ=Asia/Taipei
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV USERNAME=${USERNAME}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata \
        sudo \
        ca-certificates && \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone && \
    if getent group ${USER_GID} > /dev/null; then \
        echo "[INFO] GID ${USER_GID} already exists, reuse it."; \
    else \
        groupadd --gid ${USER_GID} ${USERNAME}; \
    fi && \
    if getent passwd ${USER_UID} > /dev/null; then \
        echo "[ERROR] UID ${USER_UID} already exists. Please use another USER_UID."; \
        exit 1; \
    else \
        useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}; \
    fi && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME} && \
    mkdir -p /workspace && \
    chown -R ${USER_UID}:${USER_GID} /workspace && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

USER ${USERNAME}

CMD ["/bin/bash"]


############################################################
# Stage 2: common_pkg_provider
# Requirement 3
# Core CLI tools + Python + pip
############################################################

FROM base AS common_pkg_provider

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        vim \
        git \
        curl \
        wget \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        autoconf \
        automake \
        flex \
        bison \
        help2man \
        perl \
        make \
        gcc \
        g++ \
        cmake \
        ninja-build \
        pkg-config \
        libfl-dev \
        zlib1g-dev \
        clang-format && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    python3 -m pip install --break-system-packages \
        numpy \
        pytest && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER ${USERNAME}

CMD ["/bin/bash"]


############################################################
# Stage 3: verilator_provider
# Build Verilator from source
############################################################

FROM common_pkg_provider AS verilator_provider

USER root

ARG VERILATOR_VERSION=5.026

WORKDIR /tmp

RUN git clone --depth 1 --branch "v${VERILATOR_VERSION}" https://github.com/verilator/verilator.git && \
    cd verilator && \
    autoconf && \
    ./configure --prefix=/opt/verilator && \
    make -j"$(nproc)" && \
    make install && \
    cd / && \
    rm -rf /tmp/verilator

ENV PATH="/opt/verilator/bin:${PATH}"

USER ${USERNAME}

CMD ["/bin/bash"]


############################################################
# Stage 4: systemc_provider
# Build SystemC 2.3.4 from source
############################################################

FROM common_pkg_provider AS systemc_provider

USER root

WORKDIR /tmp

RUN wget -O systemc-2.3.4.tar.gz https://github.com/accellera-official/systemc/archive/refs/tags/2.3.4.tar.gz && \
    tar -xzf systemc-2.3.4.tar.gz && \
    cd systemc-2.3.4 && \
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX=/opt/systemc \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    cd / && \
    rm -rf /tmp/systemc-2.3.4 /tmp/systemc-2.3.4.tar.gz

ENV SYSTEMC_HOME=/opt/systemc
ENV SYSTEMC_CXXFLAGS="-I/opt/systemc/include"
ENV SYSTEMC_LDFLAGS="-L/opt/systemc/lib -lsystemc -Wl,-rpath,/opt/systemc/lib"
ENV LD_LIBRARY_PATH="/opt/systemc/lib"

USER ${USERNAME}

CMD ["/bin/bash"]


############################################################
# Stage 5: release
# Final image
############################################################

FROM common_pkg_provider AS release

USER root

COPY --from=verilator_provider /opt/verilator /opt/verilator
COPY --from=systemc_provider /opt/systemc /opt/systemc
COPY tools/eman /usr/local/bin/eman

RUN chmod +x /usr/local/bin/eman

ENV PATH="/opt/verilator/bin:${PATH}"
ENV SYSTEMC_HOME=/opt/systemc
ENV SYSTEMC_CXXFLAGS="-I/opt/systemc/include"
ENV SYSTEMC_LDFLAGS="-L/opt/systemc/lib -lsystemc -Wl,-rpath,/opt/systemc/lib"
ENV LD_LIBRARY_PATH="/opt/systemc/lib"

WORKDIR /workspace

USER ${USERNAME}

CMD ["/bin/bash"]