FROM trzeci/emscripten-ubuntu AS builder

# Prebuild dependencies
RUN mkdir dist \
    && apt-get update -qq && apt-get -y -qq install \
        autoconf \
        automake \
        build-essential \
        cmake \
        git-core \
        libass-dev \
        libfreetype6-dev \
        libsdl2-dev \
        libtool \
        libva-dev \
        libvdpau-dev \
        libvorbis-dev \
        libxcb1-dev \
        libxcb-shm0-dev \
        libxcb-xfixes0-dev \
        pkg-config \
        texinfo \
        wget \
        yasm \
        zlib1g-dev \
    && git clone https://chromium.googlesource.com/webm/libvpx libvpx

WORKDIR /src/libvpx/

# Build libvpx
RUN emconfigure ./configure --prefix=/src/dist --disable-examples --disable-docs \
    --disable-runtime-cpu-detect --disable-multithread --disable-optimizations \
    --target=generic-gnu \
    && emmake make \
    && emmake make install

WORKDIR /src/

RUN git clone https://code.videolan.org/videolan/x264.git x264

WORKDIR /src/x264

# This is used to fix the little endian failure
# Build x264
RUN sed -i '/CPU_ENDIAN="little-endian"/!b;n;cif [ $compiler = GNU -a `basename \"$CC\"` != emcc ]; then' configure \
    && emconfigure ./configure --disable-thread --disable-asm \
        --host=i686-pc-linux-gnu \
        --disable-cli --enable-static --disable-gpl --prefix=/src/dist \
    && emmake make \
    && emmake make install

WORKDIR /src/

RUN git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg

WORKDIR /src/ffmpeg/
# --enable-libx264 and --enable-libvpx cause errors.  extra-libs picks up on these?
RUN emconfigure ./configure --prefix=/src/dist --cc="emcc" --ar="emar" --ranlib="emranlib" --nm="llvm-nm" --disable-stripping --enable-cross-compile --target-os=none --arch=x86_32 --cpu=generic --disable-ffplay --disable-asm --disable-doc --disable-devices --disable-pthreads --disable-w32threads --disable-network --disable-hwaccels --disable-parsers --disable-bsfs --disable-debug --disable-protocols --disable-indevs --disable-outdevs --enable-protocol=file --disable-ffprobe --enable-gpl --enable-nonfree --extra-libs="/src/dist/lib/libx264.a /src/dist/lib/libvpx.a" \
    && sed -i 's/define CONFIG_LIBX264 0/define CONFIG_LIBX264 1/' config.h \
    && sed -i 's/define CONFIG_LIBX264_ENCODER 0/define CONFIG_LIBX264_ENCODER 1/' config.h \
    && sed -i 's/define CONFIG_LIBX264RGB_ENCODER 0/define CONFIG_LIBX264RGB_ENCODER 1/' config.h \
    && sed -i 's/define CONFIG_H264_PARSER 0/define CONFIG_H264_PARSER 1/' config.h \
    && make -j5 && make install

WORKDIR /src/

# Move things to the dist folder
RUN cp dist/lib/libvpx.a dist/libvpx.bc \
    && cp dist/lib/libx264.a dist/libx264.bc \
    && cp ffmpeg/ffmpeg dist/ffmpeg.bc

WORKDIR /src/dist/

# Grab pre and post *.js files and build
RUN wget https://raw.githubusercontent.com/bgrins/videoconverter.js/master/build/ffmpeg_pre.js \
    && wget https://raw.githubusercontent.com/bgrins/videoconverter.js/master/build/ffmpeg_post.js \
    && emcc -s TOTAL_MEMORY=33554432 -O3 -v ffmpeg.bc libx264.bc libvpx.bc -o ffmpeg.js --pre-js ffmpeg_pre.js --post-js ffmpeg_post.js

FROM ubuntu:latest

COPY --from=builder /src/dist/ ~/dist/

LABEL maintainer="zack@linkletter.dev" \
      org.label-schema.name="ffmpeg-wasm" \
      org.label-schema.description="FFmpeg, but make it WASM." \
      org.label-schema.url="https://linkletter.dev" \
      org.label-schema.vcs-url="https://github.com/iburistu/ffmpeg-wasm" 