#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/release/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}


# Restore all .dylibs
restore_dylibs ()
{
    for dylib in "$stage/packages/lib"/release/*.dylib.disable; do
        if [ -f "$dylib" ]; then
            mv "$dylib" "${dylib%.disable}"
        fi
    done
}

pushd "$top/openal-soft"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/debug"
            mkdir -p "${stage}/lib/release"

            opts="$LL_BUILD_RELEASE"
            plainopts="$(remove_cxxstd $opts)"

            # Release Build
            mkdir -p "build"
            pushd "build"
                cmake .. -G "Ninja Multi-Config" -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_SHARED_LINKER_FLAGS="/DEBUG:FULL"

                cmake --build . --config Release --clean-first

                cp -a Release/OpenAL32.{lib,dll,exp,pdb} "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;

        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS -Wl,-headerpad_max_install_names"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                        -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                        -DCMAKE_MACOSX_RPATH=YES \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch"

                    cmake --build . --config Release
                    cmake --install . --config Release
                popd
            done

            # create fat libs
            lipo -create -output ${stage}/lib/release/libopenal.dylib ${stage}/lib/release/x86_64/libopenal.dylib ${stage}/lib/release/arm64/libopenal.dylib

            # create debug sym bundles
            pushd "${stage}/lib/release"
                install_name_tool -id "@rpath/libopenal.dylib" "libopenal.dylib"
                dsymutil libopenal.dylib
                strip -x -S libopenal.dylib
            popd

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build_release_arm64/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;

        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/release"

            # Release Build
            mkdir -p "build"
            pushd "build"
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts"

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release --clean-first

                cp -a libopenal.so* "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;
    esac
popd


pushd "$top/freealut"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/debug"
            mkdir -p "${stage}/lib/release"

            opts="$LL_BUILD_RELEASE"
            plainopts="$(remove_cxxstd $opts)"

            # Release Build
            mkdir -p "build"
            pushd "build"
                cmake .. -G "Ninja Multi-Config" -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$(cygpath -m "$stage/lib/release")" -DOPENAL_INCLUDE_DIR="$(cygpath -m "$stage/include")" \
                    -DBUILD_STATIC=OFF -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_SHARED_LINKER_FLAGS="/DEBUG:FULL"

                cmake --build . --config Release --clean-first

                cp -a Release/alut.{lib,dll,exp,pdb} "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/
        ;;

        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS -Wl,-headerpad_max_install_names"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                        -DOPENAL_LIB_DIR="$stage/lib/release" -DOPENAL_INCLUDE_DIR="$stage/include" -DBUILD_STATIC=OFF \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                        -DCMAKE_MACOSX_RPATH=YES \
                        -DCMAKE_INSTALL_PREFIX="$stage/alut_$arch"

                    cmake --build . --config Release
                    cmake --install . --config Release
                popd
            done

            # create fat libs
            lipo -create -output ${stage}/lib/release/libalut.dylib ${stage}/alut_x86_64/lib/libalut.dylib ${stage}/alut_arm64/lib/libalut.dylib

            # create debug bundles
            pushd "${stage}/lib/release"
                install_name_tool -id "@rpath/libalut.dylib" "libalut.dylib"
                dsymutil libalut.dylib
                strip -x -S libalut.dylib
            popd

            cp $stage/alut_x86_64/include/AL/*.h $stage/include/AL/
        ;;
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/debug"
            mkdir -p "${stage}/lib/release"

            # Release Build
            mkdir -p "build"
            pushd "build"
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$stage/lib/release" -DOPENAL_INCLUDE_DIR="$stage/include" \
                    -DBUILD_STATIC=OFF -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts"

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release --clean-first

                cp -a libalut.so* "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/
        ;;
    esac
popd

mkdir -p "$stage/LICENSES"
cp "$top/openal-soft/COPYING" "$stage/LICENSES/openal-soft.txt"
cp "$top/freealut/COPYING" "$stage/LICENSES/freealut.txt"
