#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

NATIVE_SOURCE_DIR="sentry-native"
COCOA_SOURCE_DIR="sentry-cocoa"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

version="8.55.1-0.7.17"
echo "${version}" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in
    # ------------------------ windows, windows64 ------------------------
    windows*)
        pushd "$NATIVE_SOURCE_DIR"
            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake -G Ninja .. \
                    -DCMAKE_BUILD_TYPE="RelWithDebInfo" \
                    -DCMAKE_CXX_STANDARD=20 \
                    -DCMAKE_INSTALL_PREFIX=$(cygpath -w "$stage/sentry")

                cmake --build . --config RelWithDebInfo
                cmake --install . --config RelWithDebInfo
            popd
        popd

        pushd "$stage/sentry"
            mkdir -p "$stage/include/sentry"
            mkdir -p "$stage/bin/release"
            mkdir -p "$stage/lib/release"

            cp -a bin/crashpad_handler.* "$stage/bin/release"
            cp -a bin/sentry.* "$stage/lib/release"
            cp -a lib/*.lib "$stage/lib/release"
            cp -a include/* "$stage/include/sentry"
        popd
    ;;

    # ------------------------- darwin, darwin64 -------------------------
    darwin*)
        pushd "$COCOA_SOURCE_DIR"
            carthage build --no-skip-current --platform macOS --verbose

            mkdir -p "$stage/lib/release"

            pushd "Carthage/Build/Mac/Sentry.framework"
                mkdir -p "$stage/include/sentry"
                mv Headers/* $stage/include/sentry/
                rm -r Headers PrivateHeaders Modules
                pushd "Versions/A/"
                    rm -r Headers PrivateHeaders Modules
                popd
            popd
            cp -a Carthage/Build/Mac/* $stage/lib/release/
        popd
    ;;

    # -------------------------- linux, linux64 --------------------------
    linux*)
        pushd "$NATIVE_SOURCE_DIR"
            # Default target per --address-size
            opts_cxx="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            opts_c="$(remove_cxxstd $opts)"

            # Release
            mkdir -p "build_release"
            pushd "build_release"
                cmake ../ -G"Ninja" \
                    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                    -DCMAKE_CXX_STANDARD=20 \
                    -DCMAKE_C_FLAGS="$opts_c" \
                    -DCMAKE_CXX_FLAGS="$opts_cxx" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release" \
                    -DSENTRY_BUILD_SHARED_LIBS=ON \
                    -DSENTRY_BACKEND="crashpad"

                cmake --build . --config RelWithDebInfo --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config RelWithDebInfo
            popd
        popd
    ;;
esac
mkdir -p "$stage/LICENSES"
cp $NATIVE_SOURCE_DIR/LICENSE "$stage/LICENSES/sentry.txt"
