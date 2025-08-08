FROM ubuntu:22.04 as blah2_env
LABEL maintainer="30hours <nathan@30hours.dev>"
LABEL org.opencontainers.image.source https://github.com/30hours/blah2

WORKDIR /blah2
ADD lib lib
RUN apt-get update && apt-get install -y software-properties-common \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y \
    g++ make cmake git curl zip unzip doxygen graphviz \
    libfftw3-dev pkg-config gfortran libhackrf-dev \
    libusb-dev libusb-1.0-0-dev \
    ninja-build \
    autoconf automake build-essential ccache cpufrequtils ethtool fort77 \
    gir1.2-gtk-3.0 gobject-introspection gpsd gpsd-clients inetutils-tools \
    libasound2-dev libboost-all-dev libcomedi-dev libcppunit-dev libfftw3-bin libfftw3-doc \
    libfontconfig1-dev libgmp-dev libgps-dev libgsl-dev liblog4cpp5-dev libncurses5 libncurses5-dev \
    libpulse-dev libqt5opengl5-dev libqwt-qt5-dev libsdl1.2-dev libtool libudev-dev libusb-dev \
    libxi-dev libxrender-dev libzmq3-dev libzmq5 ncurses-bin \
    python3-cheetah python3-click python3-click-plugins python3-click-threading python3-dev \
    python3-docutils python3-gi python3-gi-cairo python3-gps python3-lxml python3-mako python3-numpy \
    python3-opengl python3-pyqt5 python3-requests python3-scipy python3-setuptools python3-six \
    python3-sphinx python3-yaml python3-zmq python3-ruamel.yaml swig wget \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/EttusResearch/uhd.git /tmp/uhd \
    && cd /tmp/uhd \
    && git checkout v4.8.0.0 \
    && cd host \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr .. \
    && make -j4 \
    && make install \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/uhd


# install dependencies from vcpkg
ENV VCPKG_ROOT=/opt/vcpkg
RUN export PATH="/opt/vcpkg:${PATH}" \
  && git clone https://github.com/microsoft/vcpkg /opt/vcpkg \
  && if [ "$(uname -m)" = "aarch64" ]; then export VCPKG_FORCE_SYSTEM_BINARIES=1; fi \
  && /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics \
  && cd /blah2/lib && vcpkg integrate install \
  && vcpkg install --clean-after-build

# install SDRplay API
RUN export ARCH=$(uname -m) \
    && if [ "$ARCH" = "x86_64" ]; then \
        ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ARCH="arm64"; \
    fi \
    && export MAJVER="3.15" \
    && export MINVER="2" \
    && export VER=${MAJVER}.${MINVER} \
    && cd /blah2/lib/sdrplay-${VER} \
    && chmod +x SDRplay_RSP_API-Linux-${VER}.run \
    && ./SDRplay_RSP_API-Linux-${MAJVER}.${MINVER}.run --tar -xvf -C /blah2/lib/sdrplay-${VER} \
    && cp ${ARCH}/libsdrplay_api.so.${MAJVER} /usr/local/lib/libsdrplay_api.so \
    && cp ${ARCH}/libsdrplay_api.so.${MAJVER} /usr/local/lib/libsdrplay_api.so.${MAJVER} \
    && cp inc/* /usr/local/include \
    && chmod 644 /usr/local/lib/libsdrplay_api.so /usr/local/lib/libsdrplay_api.so.${MAJVER} \
    && ldconfig

# install UHD API
RUN uhd_images_downloader

# install RTL-SDR API
RUN git clone https://github.com/krakenrf/librtlsdr /opt/librtlsdr \
  && cd /opt/librtlsdr && mkdir build && cd build \
  && cmake ../ -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON && make && make install && ldconfig

FROM blah2_env as blah2
LABEL maintainer="30hours <nathan@30hours.dev>"

ADD src src
ADD test test
ADD CMakeLists.txt CMakePresets.json Doxyfile /blah2/
RUN mkdir -p build && cd build && cmake -S . --preset prod-release \
  -DCMAKE_PREFIX_PATH=$(echo /blah2/lib/vcpkg_installed/*/share) .. \
  && cd prod-release && make
RUN chmod +x bin/blah2