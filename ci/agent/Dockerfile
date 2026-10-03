# Build agent for the Jenkinsfile: Android SDK plus Flutter 3.47.6.
# (cirruslabs publishes no Flutter 3.47 image, so Flutter is cloned here.)
FROM ghcr.io/cirruslabs/android-sdk:36-ndk

ARG FLUTTER_VERSION=3.47.6
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter \
 && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN yes | sdkmanager "platforms;android-37" "ndk;28.2.13676358" "cmake;3.22.1" > /dev/null \
 && flutter config --no-analytics \
 && flutter precache --android \
 && flutter --version
