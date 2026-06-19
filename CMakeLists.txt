cmake_minimum_required(VERSION 3.20)

project(contourtty VERSION 0.0.0 LANGUAGES CXX)

option(CONTOURTTY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
  libavformat
  libavcodec
  libavutil
  libswscale
  libswresample
)

add_library(contourtty_audio STATIC
  src/audio_backend.cpp
)
target_include_directories(contourtty_audio PUBLIC src)
target_include_directories(contourtty_audio SYSTEM PUBLIC third_party)
target_compile_features(contourtty_audio PRIVATE cxx_std_20)
set_target_properties(contourtty_audio PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(contourtty_audio PUBLIC Threads::Threads)
if(APPLE)
  find_library(COREAUDIO_FRAMEWORK CoreAudio REQUIRED)
  find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
  find_library(AUDIOUNIT_FRAMEWORK AudioUnit REQUIRED)
  find_library(COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
  target_link_libraries(contourtty_audio PUBLIC
    ${COREAUDIO_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
    ${AUDIOUNIT_FRAMEWORK}
    ${COREFOUNDATION_FRAMEWORK}
  )
elseif(UNIX)
  target_link_libraries(contourtty_audio PUBLIC ${CMAKE_DL_LIBS} m)
endif()
if(MSVC)
  target_compile_options(contourtty_audio PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty_audio PRIVATE /WX)
  endif()
else()
  target_compile_options(contourtty_audio PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty_audio PRIVATE -Werror)
  endif()
endif()

add_executable(contourtty
  src/ansi.cpp
  src/cli.cpp
  src/diff_emitter.cpp
  src/glyph_ramp.cpp
  src/luminance.cpp
  src/log.cpp
  src/main.cpp
  src/media_probe.cpp
  src/png_writer.cpp
  src/player.cpp
  src/terminal.cpp
)
target_compile_features(contourtty PRIVATE cxx_std_20)
set_target_properties(contourtty PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_compile_definitions(contourtty PRIVATE CONTOURTTY_VERSION="${PROJECT_VERSION}")
target_link_libraries(contourtty PRIVATE PkgConfig::FFMPEG ZLIB::ZLIB)

if(MSVC)
  target_compile_options(contourtty PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty PRIVATE /WX)
  endif()
else()
  target_compile_options(contourtty PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty PRIVATE -Werror)
  endif()
endif()

add_library(contourtty_audio_decode STATIC
  src/audio_decode.cpp
)
target_include_directories(contourtty_audio_decode PUBLIC src)
target_compile_features(contourtty_audio_decode PRIVATE cxx_std_20)
set_target_properties(contourtty_audio_decode PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(contourtty_audio_decode PUBLIC PkgConfig::FFMPEG)
if(MSVC)
  target_compile_options(contourtty_audio_decode PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty_audio_decode PRIVATE /WX)
  endif()
else()
  target_compile_options(contourtty_audio_decode PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(contourtty_audio_decode PRIVATE -Werror)
  endif()
endif()

add_executable(audio_sine_smoke
  tools/audio_sine_smoke.cpp
)
target_compile_features(audio_sine_smoke PRIVATE cxx_std_20)
set_target_properties(audio_sine_smoke PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(audio_sine_smoke PRIVATE contourtty_audio)
if(MSVC)
  target_compile_options(audio_sine_smoke PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_sine_smoke PRIVATE /WX)
  endif()
else()
  target_compile_options(audio_sine_smoke PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_sine_smoke PRIVATE -Werror)
  endif()
endif()

add_executable(audio_file_smoke
  tools/audio_file_smoke.cpp
)
target_compile_features(audio_file_smoke PRIVATE cxx_std_20)
set_target_properties(audio_file_smoke PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(audio_file_smoke PRIVATE contourtty_audio contourtty_audio_decode)
if(MSVC)
  target_compile_options(audio_file_smoke PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_file_smoke PRIVATE /WX)
  endif()
else()
  target_compile_options(audio_file_smoke PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_file_smoke PRIVATE -Werror)
  endif()
endif()

add_executable(audio_clock_smoke
  tools/audio_clock_smoke.cpp
)
target_compile_features(audio_clock_smoke PRIVATE cxx_std_20)
set_target_properties(audio_clock_smoke PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(audio_clock_smoke PRIVATE contourtty_audio contourtty_audio_decode)
if(MSVC)
  target_compile_options(audio_clock_smoke PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_clock_smoke PRIVATE /WX)
  endif()
else()
  target_compile_options(audio_clock_smoke PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(audio_clock_smoke PRIVATE -Werror)
  endif()
endif()

enable_testing()

add_executable(luminance_tests
  tests/luminance_tests.cpp
  src/luminance.cpp
)
target_include_directories(luminance_tests PRIVATE src)
target_compile_features(luminance_tests PRIVATE cxx_std_20)
set_target_properties(luminance_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(luminance_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(luminance_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(luminance_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(luminance_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME luminance COMMAND luminance_tests)

add_executable(glyph_ramp_tests
  tests/glyph_ramp_tests.cpp
  src/glyph_ramp.cpp
)
target_include_directories(glyph_ramp_tests PRIVATE src)
target_compile_features(glyph_ramp_tests PRIVATE cxx_std_20)
set_target_properties(glyph_ramp_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(glyph_ramp_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_ramp_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(glyph_ramp_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_ramp_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME glyph_ramp COMMAND glyph_ramp_tests)

add_executable(cell_buffer_tests
  tests/cell_buffer_tests.cpp
)
target_include_directories(cell_buffer_tests PRIVATE src)
target_compile_features(cell_buffer_tests PRIVATE cxx_std_20)
set_target_properties(cell_buffer_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(cell_buffer_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(cell_buffer_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(cell_buffer_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(cell_buffer_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME cell_buffer COMMAND cell_buffer_tests)

add_executable(ansi_tests
  tests/ansi_tests.cpp
  src/ansi.cpp
)
target_include_directories(ansi_tests PRIVATE src)
target_compile_features(ansi_tests PRIVATE cxx_std_20)
set_target_properties(ansi_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(ansi_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(ansi_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(ansi_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(ansi_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME ansi COMMAND ansi_tests)

add_executable(diff_emitter_tests
  tests/diff_emitter_tests.cpp
  src/ansi.cpp
  src/diff_emitter.cpp
)
target_include_directories(diff_emitter_tests PRIVATE src)
target_compile_features(diff_emitter_tests PRIVATE cxx_std_20)
set_target_properties(diff_emitter_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(diff_emitter_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(diff_emitter_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(diff_emitter_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(diff_emitter_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME diff_emitter COMMAND diff_emitter_tests)
