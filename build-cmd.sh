#!/usr/bin/env bash

# MIT License

# Copyright (c) 2023 RyeMutt <rye@alchemyviewer.org>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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

if [ "$OSTYPE" = "cygwin" ] ; then
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

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags=""
            else
                archflags=""
            fi

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/debug"
            mkdir -p "${stage}/lib/release"

            # Debug Build
            mkdir -p "build_debug"
            pushd "build_debug"

                cmake -E env CFLAGS="$archflags /Zi" CXXFLAGS="$archflags /Zi" LDFLAGS="/DEBUG:FULL" \
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_BUILD_TYPE="Debug" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

                cmake --build . --config Debug --clean-first

                cp -a Debug/OpenAL32.{lib,dll,exp,pdb} "$stage/lib/debug/"
            popd

            # Release Build
            mkdir -p "build_release"
            pushd "build_release"

                cmake -E env CFLAGS="$archflags /O2 /Ob3 /GL /Gy /Zi" CXXFLAGS="$archflags /O2 /Ob3 /GL /Gy /Zi /std:c++17 /permissive-" LDFLAGS="/LTCG /OPT:REF /OPT:ICF /DEBUG:FULL" \
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

                cmake --build . --config Release --clean-first

                cp -a Release/OpenAL32.{lib,dll,exp,pdb} "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build_release/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;

        darwin*)
            # Setup build flags
            OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
            OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"

            # deploy target
            export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

            # Release Build
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$OPTS_X86" \
                CXXFLAGS="$OPTS_X86" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_C_FLAGS="$OPTS_X86" \
                    -DCMAKE_CXX_FLAGS="$OPTS_X86" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_x86"

                cmake --build . --config Release
                cmake --install . --config Release
            popd

            # Release Build
            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$OPTS_ARM64" \
                CXXFLAGS="$OPTS_ARM64" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_C_FLAGS="$OPTS_ARM64" \
                    -DCMAKE_CXX_FLAGS="$OPTS_ARM64" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release
            popd

            # create tage structure
            mkdir -p "$stage/include/AL"
            mkdir -p "$stage/lib/release"

            # create fat libs
            lipo -create ${stage}/release_x86/lib/libopenal.dylib ${stage}/release_arm64/lib/libopenal.dylib -output ${stage}/lib/release/libopenal.dylib

            # create debug bundles
            pushd "${stage}/lib/release"
                install_name_tool -id "@rpath/libopenal.dylib" "libopenal.dylib"
                dsymutil libopenal.dylib
                strip -x -S libopenal.dylib
            popd

            # copy includes
            cp -a $stage/release_x86/include/AL/* $stage/include/AL/

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build_release_arm64/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;

        linux*)
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

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/release"

            # Release Build
            mkdir -p "build_release"
            pushd "build_release"
                cmake -E env CFLAGS="$opts_c" CXXFLAGS="$opts_cxx" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
                    -DCMAKE_INSTALL_PREFIX="$stage"

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release --clean-first

                cp -a libopenal.so* "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/

            # Must be done after the build.  version.h is created as part of the build.
            version="$(sed -n -E 's/#define ALSOFT_VERSION "([^"]+)"/\1/p' "build_release/version.h" | tr -d '\r' )"
            echo "${version}" > "${stage}/VERSION.txt"
        ;;
    esac
popd


pushd "$top/freealut"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags=""
            else
                archflags=""
            fi

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/debug"
            mkdir -p "${stage}/lib/release"

            # Debug Build
            mkdir -p "build_debug"
            pushd "build_debug"

                cmake -E env CFLAGS="$archflags /Zi" CXXFLAGS="$archflags /Zi" LDFLAGS="/DEBUG:FULL" \
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_BUILD_TYPE="Debug" \
                    -DOPENAL_LIB_DIR="$(cygpath -m "$stage/lib/debug")" -DOPENAL_INCLUDE_DIR="$(cygpath -m "$stage/include")" \
                    -DBUILD_STATIC=OFF -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

                cmake --build . --config Debug --clean-first

                cp -a Debug/alut.{lib,dll,exp,pdb} "$stage/lib/debug/"
            popd

            # Release Build
            mkdir -p "build_release"
            pushd "build_release"

                cmake -E env CFLAGS="$archflags /O2 /Ob3 /GL /Gy /Zi" CXXFLAGS="$archflags /O2 /Ob3 /GL /Gy /Zi /std:c++17 /permissive-" LDFLAGS="/LTCG /OPT:REF /OPT:ICF /DEBUG:FULL" \
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$(cygpath -m "$stage/lib/release")" -DOPENAL_INCLUDE_DIR="$(cygpath -m "$stage/include")" \
                    -DBUILD_STATIC=OFF -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

                cmake --build . --config Release --clean-first

                cp -a Release/alut.{lib,dll,exp,pdb} "$stage/lib/release/"
            popd
            cp include/AL/*.h $stage/include/AL/
        ;;

        darwin*)
            # Deploy Targets
            X86_DEPLOY=11.0
            ARM64_DEPLOY=11.0

            # Setup build flags
            ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=${X86_DEPLOY} -msse4.2"
            ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=${ARM64_DEPLOY}"
            DEBUG_COMMON_FLAGS="-O0 -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="-O3 -g -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="-Wl,-headerpad_max_install_names"
            RELEASE_LDFLAGS="-Wl,-headerpad_max_install_names"

            # x86 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=${X86_DEPLOY}

            # Release Build
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $RELEASE_LDFLAGS" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$stage/lib/release" -DOPENAL_INCLUDE_DIR="$stage/include" -DBUILD_STATIC=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/alut_release_x86"

                cmake --build . --config Release
                cmake --install . --config Release
            popd

            # Release Build
            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_LDFLAGS" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$stage/lib/release" -DOPENAL_INCLUDE_DIR="$stage/include" -DBUILD_STATIC=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/alut_release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release
            popd

            # create fat libs
            lipo -create ${stage}/alut_release_x86/lib/libalut.dylib ${stage}/alut_release_arm64/lib/libalut.dylib -output ${stage}/lib/release/libalut.dylib

            pushd "${stage}/lib/release"
                install_name_tool -id "@rpath/libalut.dylib" "libalut.dylib"
                dsymutil libalut.dylib
                strip -x -S libalut.dylib
            popd

            # copy includes
            cp -a $stage/alut_release_arm64/include/AL/* $stage/include/AL/

            if [ -n "${APPLE_SIGNATURE:=""}" -a -n "${APPLE_KEY:=""}" -a -n "${APPLE_KEYCHAIN:=""}" ]; then
                KEYCHAIN_PATH="$HOME/Library/Keychains/$APPLE_KEYCHAIN"
                security unlock-keychain -p $APPLE_KEY $KEYCHAIN_PATH
                for dylib in $stage/lib/*/libopenal*.dylib;
                do
                    if [ -f "$dylib" ]; then
                        codesign --keychain "$KEYCHAIN_PATH" --sign "$APPLE_SIGNATURE" --force --timestamp "$dylib" || true
                    fi
                done
                for dylib in $stage/lib/*/libalut*.dylib;
                do
                    if [ -f "$dylib" ]; then
                        codesign --keychain "$KEYCHAIN_PATH" --sign "$APPLE_SIGNATURE" --force --timestamp "$dylib" || true
                    fi
                done
                security lock-keychain $KEYCHAIN_PATH
            else
                echo "Code signing not configured; skipping codesign."
            fi
        ;;
        linux*)
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

            # Create staging dirs
            mkdir -p "$stage/include/AL"
            mkdir -p "${stage}/lib/release"

            # Release Build
            mkdir -p "build_release"
            pushd "build_release"
                cmake -E env CFLAGS="$opts_c" CXXFLAGS="$opts_cxx" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DOPENAL_LIB_DIR="$stage/lib/release" -DOPENAL_INCLUDE_DIR="$stage/include" \
                    -DBUILD_STATIC=OFF -DCMAKE_INSTALL_PREFIX="$stage"

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
