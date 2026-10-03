# Build agent for the Jenkinsfile: Android SDK plus Flutter 3.47.6.
# (cirruslabs publishes no Flutter 3.47 image, so Flutter is cloned here.)
FROM ghcr.io/cirruslabs/android-sdk:36-ndk

ARG FLUTTER_VERSION=3.47.6
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter \
 && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN yes | sdkmanager "platforms;android-37.0" "ndk;28.2.13676358" "cmake;3.22.1" > /dev/null \
 && flutter config --no-analytics \
 && flutter precache --android \
 && flutter --version

# Pre-install the Gradle distribution from lumascan_app/android/gradle/wrapper/
# gradle-wrapper.properties (keep GRADLE_VERSION in step with it), so builds
# skip the wrapper download. curl also retries other GitHub CDN addresses when
# one is unreachable; the wrapper's Java downloader only tries the first.
# The wrapper looks in dists/<name>/<base36 MD5 of the URL>/.
ARG GRADLE_VERSION=9.3.1
RUN set -e; name="gradle-${GRADLE_VERSION}-all"; \
    url="https://services.gradle.org/distributions/${name}.zip"; \
    printf 'public class H { public static void main(String[] a) throws Exception { System.out.println(new java.math.BigInteger(1, java.security.MessageDigest.getInstance("MD5").digest(a[0].getBytes("UTF-8"))).toString(36)); } }' > /tmp/H.java; \
    dir="/root/.gradle/wrapper/dists/${name}/$(java /tmp/H.java "$url")"; \
    mkdir -p "$dir"; \
    curl -fsSL --retry 5 -o "$dir/${name}.zip" "$url"; \
    unzip -q "$dir/${name}.zip" -d "$dir"; \
    rm "$dir/${name}.zip" /tmp/H.java; \
    touch "$dir/${name}.zip.ok"; \
    "$dir/gradle-${GRADLE_VERSION}/bin/gradle" --version | grep '^Gradle'
