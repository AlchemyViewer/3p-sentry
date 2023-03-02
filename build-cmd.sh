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

version="7.31.3-0.5.2"
echo "${version}" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in
    # ------------------------ windows, windows64 ------------------------
    windows*)
        pushd "$NATIVE_SOURCE_DIR"
            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. \
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
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
            export MACOSX_DEPLOYMENT_TARGET=10.15

            carthage build --archive --platform macOS --verbose

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

            if [ -n "${APPLE_SIGNATURE:=""}" -a -n "${APPLE_KEY:=""}" -a -n "${APPLE_KEYCHAIN:=""}" ]; then
                KEYCHAIN_PATH="$HOME/Library/Keychains/$APPLE_KEYCHAIN"
                security unlock-keychain -p $APPLE_KEY $KEYCHAIN_PATH
                codesign --keychain "$KEYCHAIN_PATH" --sign "$APPLE_SIGNATURE" --force --timestamp "$stage/lib/release/Sentry.framework" || true
                security lock-keychain $KEYCHAIN_PATH
            else
                echo "Code signing not configured; skipping codesign."
            fi
        popd
    ;;            

    # -------------------------- linux, linux64 --------------------------
    linux*)
        pushd "$NATIVE_SOURCE_DIR"
            # Linux build environment at Alchemy comes pre-polluted with stuff that can
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

            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            # Use simple flags for crash reporter
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$opts -O2 -g -fPIC -DPIC -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"

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
                    -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                    -DCMAKE_INSTALL_PREFIX="$stage/sentry" \
                    -DSENTRY_BUILD_SHARED_LIBS=FALSE

                cmake --build . --config RelWithDebInfo --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config RelWithDebInfo
            popd

            pushd "$stage/sentry"
                mkdir -p "$stage/include/sentry"
                mkdir -p "$stage/lib/release"

                cp -a lib/*.a "$stage/lib/release"
                cp -a include/* "$stage/include/sentry"
            popd
        popd
    ;;
esac
mkdir -p "$stage/LICENSES"
cp $NATIVE_SOURCE_DIR/LICENSE "$stage/LICENSES/sentry.txt"
