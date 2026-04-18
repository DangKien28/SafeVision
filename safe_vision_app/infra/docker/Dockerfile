# ─────────────────────────────────────────────────────────────────────────────
# SafeVision — Flutter CI Build Image
# ─────────────────────────────────────────────────────────────────────────────

FROM ubuntu:24.04 AS flutter-base

ARG FLUTTER_CHANNEL=stable
ARG JAVA_VERSION=17

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
ENV PUB_CACHE=/root/.pub-cache

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        wget \
        unzip \
        xz-utils \
        zip \
        ca-certificates \
        gnupg \
        lcov \
        bc \
        openjdk-${JAVA_VERSION}-jdk-headless \
        libglu1-mesa \
    && rm -rf /var/lib/apt/lists/* \
    && git clone \
        --depth 1 \
        --branch ${FLUTTER_CHANNEL} \
        https://github.com/flutter/flutter.git \
        ${FLUTTER_HOME} \
    && flutter config \
        --no-analytics \
        --no-enable-web \
        --no-enable-macos-desktop \
        --no-enable-linux-desktop \
        --no-enable-windows-desktop \
    && flutter precache --android --no-ios \
    && flutter doctor -v

# ─────────────────────────────────────────────────────────────────────────────
FROM flutter-base AS deps

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS test-runner

COPY . .

CMD ["flutter", "test", "--coverage", "--reporter=github", "--timeout=60s", "test/"]

# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS android-builder

ARG ANDROID_SDK_VERSION=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_COMPILE_SDK=36

ARG ANDROID_BUILD_TOOLS=36.0.0

ARG ANDROID_NDK_VERSION=27.0.12077973

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

# Merged into a single RUN to satisfy docker:S7031 (consecutive RUN layers).
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q "https://dl.google.com/android/repository/${ANDROID_SDK_VERSION}" \
         -O /tmp/cmdlinetools.zip \
    && unzip -q /tmp/cmdlinetools.zip -d /tmp/cmdlinetools \
    && mv /tmp/cmdlinetools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdlinetools.zip \
    && yes | sdkmanager --licenses \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "ndk;${ANDROID_NDK_VERSION}"

COPY . .

CMD ["flutter", "build", "apk", "--release", "--split-per-abi"]