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

version="8.42.1-0.7.17"
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
                    -DCMAKE_CXX_STANDARD=17 \
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
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS

            # Default target per --address-size
            opts_c="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"
            opts_cxx="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CXXFLAGS}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Release
            mkdir -p "build_release"
            pushd "build_release"
                cmake ../ -G"Ninja" \
                    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                    -DCMAKE_CXX_STANDARD=17 \
                    -DCMAKE_C_FLAGS="$opts_c" \
                    -DCMAKE_CXX_FLAGS="$opts_cxx" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DSENTRY_BUILD_SHARED_LIBS=FALSE \
                    -DSENTRY_BACKEND="breakpad"

                cmake --build . --config RelWithDebInfo --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config RelWithDebInfo
            popd
        popd
    ;;
esac
mkdir -p "$stage/LICENSES"
cp $NATIVE_SOURCE_DIR/LICENSE "$stage/LICENSES/sentry.txt"
