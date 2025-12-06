@echo off

if not exist depot_tools (
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
)

set COMMAND_DIR=%~dp0
set PATH=%cd%\depot_tools;%PATH%
set WEBRTC_VERSION=7390
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
set GYP_GENERATORS=ninja,msvs-ninja
set GYP_MSVS_VERSION=2022
set OUTPUT_DIR=out
set ARTIFACTS_DIR=%cd%\artifacts
set SRC_DIR=%cd%\src
set PYPI_URL=https://artifactory.prd.it.unity3d.com/artifactory/api/pypi/pypi/simple
set vs2022_install=C:\Program Files\Microsoft Visual Studio\2022\Community

if not exist src (
  call fetch.bat --nohooks webrtc
  cd src
  call git.bat config --system core.longpaths true
  call git.bat checkout  refs/remotes/branch-heads/%WEBRTC_VERSION%
  cd ..
  call gclient.bat sync -D --force --reset
)

@REM rem add jsoncpp
@REM patch -N "src\BUILD.gn" < "%COMMAND_DIR%\patches\add_jsoncpp.patch"

@REM rem fix towupper
@REM patch -N "src\modules\desktop_capture\win\full_screen_win_application_handler.cc" < "%COMMAND_DIR%\patches\fix_towupper.patch"

@REM rem fix abseil
@REM patch -N "src\third_party\abseil-cpp/absl/base/config.h" < "%COMMAND_DIR%\patches\fix_abseil.patch"

@REM rem fix task_queue_base
@REM patch -N "src\api\task_queue\task_queue_base.h" < "%COMMAND_DIR%\patches\fix_task_queue_base.patch"

@REM rem fix SetRawImagePlanes() in LibvpxVp8Encoder
@REM patch -N "src\modules\video_coding\codecs\vp8\libvpx_vp8_encoder.cc" < "%COMMAND_DIR%\patches\libvpx_vp8_encoder.patch"

rem remove artifacts
rmdir /S /Q "%ARTIFACTS_DIR%"
mkdir "%ARTIFACTS_DIR%\lib"

setlocal enabledelayedexpansion

cd src
for %%i in (x64) do (
  mkdir "%ARTIFACTS_DIR%/lib/%%i"
  for %%j in (true false) do (
    set profile=
    if true==%%j (
      set profile=Release
    ) else (
      set profile=Debug
    )

    set output_profile="%OUTPUT_DIR%\%%i\!profile!"

    rem generate ninja for release
    echo Generating build files !output_profile!
    call gn.bat gen "!output_profile!" ^
      --args="is_debug=%%j is_clang=true target_cpu=\"%%i\" use_custom_libcxx=false rtc_include_tests=false rtc_build_examples=false rtc_use_h264=true rtc_use_h265=true proprietary_codecs=true symbol_level=0 enable_iterator_debugging=false use_cxx17=true"

    rem build
    call ninja.bat -C !output_profile! webrtc
    set filename=
    if true==%%j (
      set filename=webrtcd.lib
    ) else (
      set filename=webrtc.lib
    )

    rem copy static library for release build
    copy "!output_profile!\obj\webrtc.lib" "%ARTIFACTS_DIR%\lib\%%i\!filename!"
  )
)

cd ..
endlocal


rem generate license
call python.bat "%SRC_DIR%\tools_webrtc\libs\generate_licenses.py" ^
  --target :webrtc %ARTIFACTS_DIR% %ARTIFACTS_DIR%

rem unescape license
powershell -File "%COMMAND_DIR%\Unescape.ps1" "%ARTIFACTS_DIR%\LICENSE.md"

rem copy header
xcopy src\*.h "%ARTIFACTS_DIR%\include" /C /S /I /F /H

xcopy src\*.inc "%ARTIFACTS_DIR%\include" /C /S /I /F /H

rem create zip
cd %ARTIFACTS_DIR%
7z a -tzip webrtc-win.zip *