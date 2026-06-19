cmake_minimum_required(VERSION 3.20)

project(contourtty VERSION 0.0.0 LANGUAGES CXX)

option(CONTOURTTY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

find_package(PkgConfig REQUIRED)
find_package(ZLIB REQUIRED)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
  libavformat
  libavcodec
  libavutil
  libswscale
)

add_executable(contourtty
  src/cli.cpp
  src/glyph_ramp.cpp
  src/luminance.cpp
  src/log.cpp
  src/main.cpp
  src/media_probe.cpp
  src/png_writer.cpp
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
