# ─────────────────────────────────────────────────────────────────────────────
# SafeVision — Flutter CI Build Image
#
# Used for: local CI simulation, custom runners, Docker-based testing.
#
# Multi-stage build with four stages:
#   flutter-base    → SDK + system dependencies
#   deps            → pub packages (cached separately from source)
#   test-runner     → runs flutter test with coverage
#   android-builder → builds release/debug APK
#
# By isolating deps into its own stage, the pub packages layer is not
# invalidated by source code changes — only when pubspec.lock changes.
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: Flutter SDK base
# Use the stable channel without a pinned version to avoid build failures
# caused by an unavailable version. If pinning is required, change the ARG
# below and check https://docs.flutter.dev/release/archive first.
FROM ubuntu:24.04 AS flutter-base

ARG FLUTTER_CHANNEL=stable
ARG JAVA_VERSION=17

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
ENV PUB_CACHE=/root/.pub-cache

# System dependencies — installed in a single layer to keep image size small
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
    && rm -rf /var/lib/apt/lists/*

# Install Flutter from the stable channel
RUN git clone \
    --depth 1 \
    --branch ${FLUTTER_CHANNEL} \
    https://github.com/flutter/flutter.git \
    ${FLUTTER_HOME}

# Pre-warm Flutter: download the Dart SDK, tools, and platform artifacts.
# Only Android is pre-cached — iOS artifacts are not available on Linux runners.
RUN flutter config \
        --no-analytics \
        --no-enable-web \
        --no-enable-macos-desktop \
        --no-enable-linux-desktop \
        --no-enable-windows-desktop \
    && flutter precache --android --no-ios \
    && flutter doctor -v

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Project dependencies
# Copy only pubspec.yaml and pubspec.lock first so this layer is cached as
# long as the lock file does not change — saves significant build time.
# ─────────────────────────────────────────────────────────────────────────────
FROM flutter-base AS deps

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: Test runner
# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS test-runner

COPY . .

# Default: run all tests with a coverage report
CMD ["flutter", "test", "--coverage", "--reporter=github", "--timeout=60s", "test/"]

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4: Android builder
# Installs the Android SDK and NDK required to build the APK.
# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS android-builder

ARG ANDROID_SDK_VERSION=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=34.0.0

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q "https://dl.google.com/android/repository/${ANDROID_SDK_VERSION}" \
         -O /tmp/cmdlinetools.zip \
    && unzip -q /tmp/cmdlinetools.zip -d /tmp/cmdlinetools \
    && mv /tmp/cmdlinetools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdlinetools.zip

RUN yes | sdkmanager --licenses \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "ndk;27.0.12077973"

COPY . .

CMD ["flutter", "build", "apk", "--release", "--split-per-abi"]