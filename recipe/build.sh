#!/bin/bash

set -euxo pipefail

export TENSORSTORE_USE_SYSTEM_NUMPY=1

if [[ $target_platform == "linux-ppc64le" ]]; then
export CFLAGS=$(echo $CFLAGS | sed -e 's/-mtune=power8//g' | sed -e 's/-mcpu=power8//g' )
export CXXFLAGS=$(echo $CXXFLAGS | sed -e 's/-mtune=power8//g' | sed -e 's/-mcpu=power8//g' )
export DEBUG_CFLAGS=$(echo $DEBUG_CFLAGS | sed -e 's/-mtune=power8//g' | sed -e 's/-mcpu=power8//g' )
export DEBUG_CXXFLAGS=$(echo $DEBUG_CXXFLAGS | sed -e 's/-mtune=power8//g' | sed -e 's/-mcpu=power8//g' )
fi

source gen-bazel-toolchain
if [[ $target_platform =~ osx.* && -d "$CONDA_BUILD_SYSROOT/usr/include/curl" ]]; then
    mv "$CONDA_BUILD_SYSROOT/usr/include/curl" "$CONDA_BUILD_SYSROOT/usr/include/curl.do-not-use"
fi

system_libs="com_google_boringssl"
system_libs+=",org_sourceware_bzip2"
system_libs+=",org_blosc_cblosc"
system_libs+=",se_curl"
system_libs+=",jpeg"
system_libs+=",png"
system_libs+=",libwebp"
system_libs+=",org_lz4"
system_libs+=",org_tukaani_xz"
system_libs+=",net_zlib"
system_libs+=",com_github_pybind_pybind11"
system_libs+=",com_github_nlohmann_json"
system_libs+=",org_aomedia_avif"
# system_libs+=",com_google_absl"
export TENSORSTORE_SYSTEM_LIBS="$system_libs"

build_options=""
build_options+=" --crosstool_top=//bazel_toolchain:toolchain"
build_options+=" --logging=6"
build_options+=" --verbose_failures"
build_options+=" --toolchain_resolution_debug=.*"
build_options+=" --enable_workspace"  # Bazel 8 compatibility: use WORKSPACE instead of MODULE.bazel
build_options+=" --noenable_bzlmod"
build_options+=" --local_cpu_resources=${CPU_COUNT}"
build_options+=" --cpu=${TARGET_CPU}"
build_options+=" --subcommands"  # comment out for debugging
export TENSORSTORE_BAZEL_BUILD_OPTIONS="$build_options"

# TODO: figure out why we need both TENSORSTORE_BAZEL_BUILD_OPTIONS and a bazelrc
cat > .bazelrc <<EOF
build --crosstool_top=//custom_toolchain:toolchain
build --logging=6
build --verbose_failures
build --local_cpu_resources=${CPU_COUNT}
EOF

# replace bundled baselisk with a simpler forwarder to our own bazel in build prefix
export BAZEL_EXE="${BUILD_PREFIX}/bin/bazel"
export TENSORSTORE_BAZELISK="${RECIPE_DIR}/bazelisk_shim.py"

${PYTHON} -m pip install . -vv

# Save vendored licenses
mkdir -p licenses
ls bazel-work/external/

copy_vendored_license() {
    local out_name="$1"
    shift
    local repo
    local candidate
    for repo in "$@"; do
        for candidate in LICENSE LICENSE.txt COPYING COPYING.txt; do
            if [[ -f "bazel-work/external/${repo}/${candidate}" ]]; then
                cp "bazel-work/external/${repo}/${candidate}" "${SRC_DIR}/licenses/${out_name}"
                return 0
            fi
        done
    done
    echo "Could not locate vendored license for ${out_name}. Checked repos: $*" >&2
    return 1
}

copy_vendored_license abseil-cpp.txt abseil-cpp com_google_absl
copy_vendored_license re2.txt re2 com_google_re2
copy_vendored_license riegeli.txt riegeli com_google_riegeli
copy_vendored_license net_sourceforge_half.txt net_sourceforge_half

# Clean up a bit to speed-up prefix post-processing
bazel clean || true
bazel shutdown || true
