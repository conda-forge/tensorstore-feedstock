:: Windows has no `bazel-toolchain` package (it only generates GCC/Clang
:: crosstool configs), so unlike build.sh we do not source gen-bazel-toolchain
:: or pass any --crosstool_top/--platforms flags here. Bazel auto-detects the
:: MSVC toolchain natively on Windows, and tensorstore's own .bazelrc already
:: has a `build:windows` config for it (activated via
:: --enable_platform_specific_config, which is also already on by default).
:: We also do not set TENSORSTORE_SYSTEM_LIBS on Windows: the "use system
:: libs" machinery (recipe/patches/0003-use-system-libs.patch) links via
:: Unix-style `-lfoo` flags, which MSVC's linker does not understand, so on
:: this platform every third-party C library is built from the vendored
:: sources bundled by tensorstore itself -- the same thing upstream does to
:: produce its own official win_amd64 wheels.

set "TENSORSTORE_USE_SYSTEM_NUMPY=1"

:: Bazel always needs a real Bash even on Windows (used by genrules and by
:: some third-party repo rules), and it needs to be told where MSVC lives.
:: m2-bash (build dep) and the activated vs2022 compiler provide these.
set "BAZEL_SH=%BUILD_PREFIX%\Library\usr\bin\bash.exe"
set "BAZEL_VC=%VSINSTALLDIR%VC"
set "BAZEL_VS=%VSINSTALLDIR%"

set "BAZEL_EXE=%BUILD_PREFIX%\Library\bin\bazel.exe"
set "TENSORSTORE_BAZELISK=%RECIPE_DIR%\bazelisk_shim.py"

:: Bazel's own output tree plus tensorstore's third-party dependency graph
:: (grpc, aws-sdk-cpp, protobuf, abseil, ...) easily exceeds Windows' 260
:: character MAX_PATH. Keep both the output base and TEMP short.
if not exist "%SYSTEMDRIVE%\bld" mkdir "%SYSTEMDRIVE%\bld"
set "TEMP=%SYSTEMDRIVE%\bld"
set "TMP=%SYSTEMDRIVE%\bld"
set "TENSORSTORE_BAZEL_STARTUP_OPTIONS=--output_base=%SYSTEMDRIVE%\bzlout"

%PYTHON% -m pip install . -vv
if errorlevel 1 exit /b 1

:: Save vendored licenses
if not exist licenses mkdir licenses

call :copy_vendored_license abseil-cpp.txt abseil-cpp com_google_absl
if errorlevel 1 exit /b 1
call :copy_vendored_license re2.txt re2 com_google_re2
if errorlevel 1 exit /b 1
call :copy_vendored_license riegeli.txt riegeli com_google_riegeli
if errorlevel 1 exit /b 1
call :copy_vendored_license net_sourceforge_half.txt net_sourceforge_half
if errorlevel 1 exit /b 1

:: Clean up a bit to speed-up prefix post-processing
%BAZEL_EXE% --output_base=%SYSTEMDRIVE%\bzlout clean
%BAZEL_EXE% --output_base=%SYSTEMDRIVE%\bzlout shutdown

exit /b 0

:copy_vendored_license
setlocal enabledelayedexpansion
set "out_name=%~1"
shift
:copy_vendored_license_repo_loop
if "%~1"=="" (
    echo Could not locate vendored license for %out_name% >&2
    endlocal
    exit /b 1
)
for %%C in (LICENSE LICENSE.txt COPYING COPYING.txt) do (
    if exist "bazel-work\external\%~1\%%C" (
        copy /Y "bazel-work\external\%~1\%%C" "%SRC_DIR%\licenses\%out_name%" >nul
        endlocal
        exit /b 0
    )
)
shift
goto :copy_vendored_license_repo_loop
