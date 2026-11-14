# Headless Linux verification for the tesseract_ocr plugin.
#
# Builds the example app for Linux — which compiles and links the plugin's C++
# Flutter target against the system Tesseract/Leptonica — then runs a real OCR
# integration test on a Linux device (under Xvfb, so no physical display is
# required).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git unzip xz-utils zip \
      build-essential clang cmake ninja-build pkg-config \
      libgtk-3-dev liblzma-dev libstdc++-12-dev libglu1-mesa-dev \
      xvfb xauth \
      libtesseract-dev libleptonica-dev tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
    && flutter config --enable-linux-desktop --no-analytics \
    && flutter --disable-analytics

WORKDIR /app
COPY . /app
RUN cd example && flutter pub get

# path_provider's getApplicationDocumentsDirectory needs XDG user dirs. A headless
# container has none, so seed them (mirrors a real Linux desktop session).
ENV XDG_DOCUMENTS_DIR=/root/Documents
RUN mkdir -p /root/Documents /root/.config && \
    printf 'XDG_DOCUMENTS_DIR="/root/Documents"\n' > /root/.config/user-dirs.dirs

# Compile + link the C++ plugin, then run the OCR integration test on a real
# Linux device. Xvfb supplies the display Flutter needs; no physical monitor.
CMD ["bash", "-lc", "set -e; cd /app/example && flutter build linux --release && xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 flutter test integration_test/tesseract_ocr_linux_test.dart -d linux --reporter expanded"]