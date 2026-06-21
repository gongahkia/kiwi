cmake_minimum_required(VERSION 3.20)

project(contourtty VERSION 0.0.0 LANGUAGES CXX)

option(CONTOURTTY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
option(CONTOURTTY_LIGHT "Build without optional GPU/protocol backends" OFF)

include(GNUInstallDirs)
add_compile_definitions(
  CONTOURTTY_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
  CONTOURTTY_DATA_DIR="${CMAKE_INSTALL_FULL_DATADIR}/contourtty"
)

set(CONTOURTTY_GPU_SOBEL_SOURCE src/gpu_sobel_stub.cpp)
set(CONTOURTTY_GPU_LIBS)
if(APPLE AND NOT CONTOURTTY_LIGHT)
  enable_language(OBJCXX)
  find_library(METAL_FRAMEWORK Metal REQUIRED)
  find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
  set(CONTOURTTY_GPU_SOBEL_SOURCE src/gpu_sobel_metal.mm)
  set(CONTOURTTY_GPU_LIBS ${METAL_FRAMEWORK} ${FOUNDATION_FRAMEWORK})
  set_source_files_properties(src/gpu_sobel_metal.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
endif()

find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
  libavformat
  libavcodec
  libavdevice
  libavutil
  libswscale
  libswresample
)
pkg_check_modules(FREETYPE REQUIRED IMPORTED_TARGET freetype2)

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
  src/auto_mode.cpp
  src/asciinema_in.cpp
  src/asciinema_source.cpp
  src/asciinema_vte.cpp
  src/base64.cpp
  src/bandwidth_guard.cpp
  src/block_sad.cpp
  src/braille_renderer.cpp
  src/captions.cpp
  src/cli.cpp
  src/cli_spec.cpp
  src/color_dither.cpp
  src/color_mode.cpp
  src/color_quantization.cpp
  src/crosshatch.cpp
  src/diff_emitter.cpp
  src/etf.cpp
  src/frame_sampling.cpp
  src/glyph_font.cpp
  src/glyph_hog.cpp
  src/glyph_kdtree.cpp
  src/glyph_ramp.cpp
  src/glyph_sdf.cpp
  src/glyph_shape.cpp
  src/graphics_alignment.cpp
  src/graphics_emitter.cpp
  src/graph_yaml.cpp
  src/image_grid.cpp
  ${CONTOURTTY_GPU_SOBEL_SOURCE}
  src/halfblock_renderer.cpp
  src/hysteresis.cpp
  src/hybrid_emitter.cpp
  src/iterm_inline.cpp
  src/kuwahara.cpp
  src/kitty_graphics.cpp
  src/lic.cpp
  src/line_ligatures.cpp
  src/luminance.cpp
  src/log.cpp
  src/main.cpp
  src/media_input.cpp
  src/media_probe.cpp
  src/octant_renderer.cpp
  src/optical_flow.cpp
  src/overlay_compose.cpp
  src/posterize.cpp
  src/png_writer.cpp
  src/player.cpp
  src/raster_compose.cpp
  src/render_mode.cpp
  src/render_graph.cpp
  src/render_layout.cpp
  src/renderer.cpp
  src/scene_source.cpp
  src/sextant_renderer.cpp
  src/split.cpp
  src/stdin_data.cpp
  src/stipple.cpp
  src/structure_edges.cpp
  src/structure_overlay.cpp
  src/structure_sampling.cpp
  src/stream_resolver.cpp
  src/terminal.cpp
  src/terminal_caps.cpp
  src/video_decoder.cpp
  src/warp_history.cpp
)
target_include_directories(contourtty SYSTEM PRIVATE third_party)
target_compile_features(contourtty PRIVATE cxx_std_20)
set_target_properties(contourtty PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_compile_definitions(contourtty PRIVATE CONTOURTTY_VERSION="${PROJECT_VERSION}")
target_link_libraries(contourtty PRIVATE PkgConfig::FFMPEG PkgConfig::FREETYPE ZLIB::ZLIB contourtty_audio contourtty_audio_decode ${CONTOURTTY_GPU_LIBS})

install(TARGETS contourtty
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES README.md LICENSE CONTRIBUTING.md
  DESTINATION ${CMAKE_INSTALL_DOCDIR}
)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/docs/demo-source.md")
  install(FILES docs/demo-source.md
    DESTINATION ${CMAKE_INSTALL_DOCDIR}/docs
  )
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/docs/contourtty.1")
  install(FILES docs/contourtty.1
    DESTINATION ${CMAKE_INSTALL_MANDIR}/man1
  )
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/share/contourtty")
  install(DIRECTORY share/contourtty
    DESTINATION ${CMAKE_INSTALL_DATADIR}
  )
endif()

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

add_executable(evolve_charset
  tools/evolve_charset.cpp
)
target_compile_features(evolve_charset PRIVATE cxx_std_20)
set_target_properties(evolve_charset PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(evolve_charset PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(evolve_charset PRIVATE /WX)
  endif()
else()
  target_compile_options(evolve_charset PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(evolve_charset PRIVATE -Werror)
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

add_executable(glyph_shape_tests
  tests/glyph_shape_tests.cpp
  src/glyph_font.cpp
  src/glyph_shape.cpp
)
target_include_directories(glyph_shape_tests PRIVATE src)
target_compile_features(glyph_shape_tests PRIVATE cxx_std_20)
set_target_properties(glyph_shape_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(glyph_shape_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_shape_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(glyph_shape_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_shape_tests PRIVATE -Werror)
  endif()
endif()
target_link_libraries(glyph_shape_tests PRIVATE PkgConfig::FREETYPE)
add_test(NAME glyph_shape COMMAND glyph_shape_tests)

add_executable(glyph_font_tests
  tests/glyph_font_tests.cpp
  src/glyph_font.cpp
  src/glyph_shape.cpp
)
target_include_directories(glyph_font_tests PRIVATE src)
target_compile_features(glyph_font_tests PRIVATE cxx_std_20)
set_target_properties(glyph_font_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(glyph_font_tests PRIVATE PkgConfig::FREETYPE)
if(MSVC)
  target_compile_options(glyph_font_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_font_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(glyph_font_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_font_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME glyph_font COMMAND glyph_font_tests)

add_executable(glyph_hog_tests
  tests/glyph_hog_tests.cpp
  src/glyph_font.cpp
  src/glyph_hog.cpp
  src/glyph_shape.cpp
)
target_include_directories(glyph_hog_tests PRIVATE src)
target_compile_features(glyph_hog_tests PRIVATE cxx_std_20)
set_target_properties(glyph_hog_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(glyph_hog_tests PRIVATE PkgConfig::FREETYPE)
if(MSVC)
  target_compile_options(glyph_hog_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_hog_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(glyph_hog_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_hog_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME glyph_hog COMMAND glyph_hog_tests)

add_executable(glyph_sdf_tests
  tests/glyph_sdf_tests.cpp
  src/glyph_font.cpp
  src/glyph_sdf.cpp
  src/glyph_shape.cpp
)
target_include_directories(glyph_sdf_tests PRIVATE src)
target_compile_features(glyph_sdf_tests PRIVATE cxx_std_20)
set_target_properties(glyph_sdf_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(glyph_sdf_tests PRIVATE PkgConfig::FREETYPE)
if(MSVC)
  target_compile_options(glyph_sdf_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_sdf_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(glyph_sdf_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(glyph_sdf_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME glyph_sdf COMMAND glyph_sdf_tests)

add_executable(kd_tree_tests
  tests/kd_tree_tests.cpp
  src/glyph_font.cpp
  src/glyph_kdtree.cpp
  src/glyph_shape.cpp
)
target_include_directories(kd_tree_tests PRIVATE src)
target_include_directories(kd_tree_tests SYSTEM PRIVATE third_party)
target_compile_features(kd_tree_tests PRIVATE cxx_std_20)
set_target_properties(kd_tree_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(kd_tree_tests PRIVATE PkgConfig::FREETYPE)
if(MSVC)
  target_compile_options(kd_tree_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kd_tree_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(kd_tree_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kd_tree_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME kd_tree COMMAND kd_tree_tests)

add_executable(cli_tests
  tests/cli_tests.cpp
  src/cli.cpp
  src/cli_spec.cpp
  src/glyph_ramp.cpp
  src/image_grid.cpp
  src/scene_source.cpp
  src/split.cpp
  src/stdin_data.cpp
)
target_include_directories(cli_tests PRIVATE src)
target_compile_features(cli_tests PRIVATE cxx_std_20)
set_target_properties(cli_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(cli_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(cli_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(cli_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(cli_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME cli COMMAND cli_tests)

add_executable(help_manpage_parity_tests
  tests/help_manpage_parity_tests.cpp
  src/cli.cpp
  src/cli_spec.cpp
  src/glyph_ramp.cpp
  src/image_grid.cpp
  src/scene_source.cpp
  src/split.cpp
  src/stdin_data.cpp
)
target_include_directories(help_manpage_parity_tests PRIVATE src)
target_compile_definitions(help_manpage_parity_tests PRIVATE CONTOURTTY_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
target_compile_features(help_manpage_parity_tests PRIVATE cxx_std_20)
set_target_properties(help_manpage_parity_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(help_manpage_parity_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(help_manpage_parity_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(help_manpage_parity_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(help_manpage_parity_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME help_manpage_parity COMMAND help_manpage_parity_tests)

add_executable(color_mode_tests
  tests/color_mode_tests.cpp
  src/color_mode.cpp
)
target_include_directories(color_mode_tests PRIVATE src)
target_compile_features(color_mode_tests PRIVATE cxx_std_20)
set_target_properties(color_mode_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(color_mode_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_mode_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(color_mode_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_mode_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME color_mode COMMAND color_mode_tests)

add_executable(color_quantization_tests
  tests/color_quantization_tests.cpp
  src/color_quantization.cpp
)
target_include_directories(color_quantization_tests PRIVATE src)
target_compile_features(color_quantization_tests PRIVATE cxx_std_20)
set_target_properties(color_quantization_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(color_quantization_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_quantization_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(color_quantization_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_quantization_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME color_quantization COMMAND color_quantization_tests)

add_executable(color_dither_tests
  tests/color_dither_tests.cpp
  src/color_dither.cpp
  src/color_quantization.cpp
)
target_include_directories(color_dither_tests PRIVATE src)
target_compile_features(color_dither_tests PRIVATE cxx_std_20)
set_target_properties(color_dither_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(color_dither_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_dither_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(color_dither_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(color_dither_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME color_dither COMMAND color_dither_tests)

add_executable(braille_renderer_tests
  tests/braille_renderer_tests.cpp
  src/braille_renderer.cpp
  src/frame_sampling.cpp
  src/luminance.cpp
)
target_include_directories(braille_renderer_tests PRIVATE src)
target_compile_features(braille_renderer_tests PRIVATE cxx_std_20)
set_target_properties(braille_renderer_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(braille_renderer_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(braille_renderer_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(braille_renderer_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(braille_renderer_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME braille_renderer COMMAND braille_renderer_tests)

add_executable(halfblock_renderer_tests
  tests/halfblock_renderer_tests.cpp
  src/frame_sampling.cpp
  src/halfblock_renderer.cpp
)
target_include_directories(halfblock_renderer_tests PRIVATE src)
target_compile_features(halfblock_renderer_tests PRIVATE cxx_std_20)
set_target_properties(halfblock_renderer_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(halfblock_renderer_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(halfblock_renderer_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(halfblock_renderer_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(halfblock_renderer_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME halfblock_renderer COMMAND halfblock_renderer_tests)

add_executable(block_sad_tests
  tests/block_sad_tests.cpp
  src/block_sad.cpp
  src/frame_sampling.cpp
  src/luminance.cpp
)
target_include_directories(block_sad_tests PRIVATE src)
target_compile_features(block_sad_tests PRIVATE cxx_std_20)
set_target_properties(block_sad_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(block_sad_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(block_sad_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(block_sad_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(block_sad_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME block_sad COMMAND block_sad_tests)

add_executable(octant_renderer_tests
  tests/octant_renderer_tests.cpp
  src/frame_sampling.cpp
  src/luminance.cpp
  src/octant_renderer.cpp
)
target_include_directories(octant_renderer_tests PRIVATE src)
target_compile_features(octant_renderer_tests PRIVATE cxx_std_20)
set_target_properties(octant_renderer_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(octant_renderer_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(octant_renderer_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(octant_renderer_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(octant_renderer_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME octant_renderer COMMAND octant_renderer_tests)

add_executable(sextant_renderer_tests
  tests/sextant_renderer_tests.cpp
  src/frame_sampling.cpp
  src/luminance.cpp
  src/sextant_renderer.cpp
)
target_include_directories(sextant_renderer_tests PRIVATE src)
target_compile_features(sextant_renderer_tests PRIVATE cxx_std_20)
set_target_properties(sextant_renderer_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(sextant_renderer_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(sextant_renderer_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(sextant_renderer_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(sextant_renderer_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME sextant_renderer COMMAND sextant_renderer_tests)

add_executable(render_layout_tests
  tests/render_layout_tests.cpp
  src/render_layout.cpp
)
target_include_directories(render_layout_tests PRIVATE src)
target_compile_features(render_layout_tests PRIVATE cxx_std_20)
set_target_properties(render_layout_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(render_layout_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_layout_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(render_layout_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_layout_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME render_layout COMMAND render_layout_tests)

add_executable(render_graph_tests
  tests/render_graph_tests.cpp
  src/render_graph.cpp
)
target_include_directories(render_graph_tests PRIVATE src)
target_compile_features(render_graph_tests PRIVATE cxx_std_20)
set_target_properties(render_graph_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(render_graph_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_graph_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(render_graph_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_graph_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME render_graph COMMAND render_graph_tests)

add_executable(split_tests
  tests/split_tests.cpp
  src/split.cpp
)
target_include_directories(split_tests PRIVATE src)
target_compile_features(split_tests PRIVATE cxx_std_20)
set_target_properties(split_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(split_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(split_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(split_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(split_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME split COMMAND split_tests)

add_executable(golden_frame_tests
  tests/golden_frame_tests.cpp
  src/block_sad.cpp
  src/braille_renderer.cpp
  src/crosshatch.cpp
  src/etf.cpp
  src/frame_sampling.cpp
  src/glyph_font.cpp
  src/glyph_hog.cpp
  src/glyph_ramp.cpp
  src/glyph_sdf.cpp
  src/glyph_shape.cpp
  src/graph_yaml.cpp
  ${CONTOURTTY_GPU_SOBEL_SOURCE}
  src/halfblock_renderer.cpp
  src/hysteresis.cpp
  src/kuwahara.cpp
  src/lic.cpp
  src/line_ligatures.cpp
  src/luminance.cpp
  src/octant_renderer.cpp
  src/optical_flow.cpp
  src/posterize.cpp
  src/render_graph.cpp
  src/render_layout.cpp
  src/renderer.cpp
  src/sextant_renderer.cpp
  src/stipple.cpp
  src/structure_edges.cpp
  src/structure_overlay.cpp
  src/structure_sampling.cpp
  src/warp_history.cpp
)
target_include_directories(golden_frame_tests PRIVATE src)
target_compile_features(golden_frame_tests PRIVATE cxx_std_20)
set_target_properties(golden_frame_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(golden_frame_tests PRIVATE Threads::Threads PkgConfig::FREETYPE ${CONTOURTTY_GPU_LIBS})
if(MSVC)
  target_compile_options(golden_frame_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(golden_frame_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(golden_frame_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(golden_frame_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME golden_frame COMMAND golden_frame_tests)

add_executable(etf_tests
  tests/etf_tests.cpp
  src/etf.cpp
)
target_include_directories(etf_tests PRIVATE src)
target_compile_features(etf_tests PRIVATE cxx_std_20)
set_target_properties(etf_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(etf_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(etf_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(etf_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(etf_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME etf COMMAND etf_tests)

add_executable(kuwahara_tests
  tests/kuwahara_tests.cpp
  src/kuwahara.cpp
)
target_include_directories(kuwahara_tests PRIVATE src)
target_compile_features(kuwahara_tests PRIVATE cxx_std_20)
set_target_properties(kuwahara_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(kuwahara_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kuwahara_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(kuwahara_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kuwahara_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME kuwahara COMMAND kuwahara_tests)

add_executable(crosshatch_tests
  tests/crosshatch_tests.cpp
  src/crosshatch.cpp
  src/luminance.cpp
  src/structure_edges.cpp
  src/structure_sampling.cpp
)
target_include_directories(crosshatch_tests PRIVATE src)
target_compile_features(crosshatch_tests PRIVATE cxx_std_20)
set_target_properties(crosshatch_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(crosshatch_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(crosshatch_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(crosshatch_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(crosshatch_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME crosshatch COMMAND crosshatch_tests)

add_executable(stipple_tests
  tests/stipple_tests.cpp
  src/frame_sampling.cpp
  src/luminance.cpp
  src/octant_renderer.cpp
  src/stipple.cpp
)
target_include_directories(stipple_tests PRIVATE src)
target_compile_features(stipple_tests PRIVATE cxx_std_20)
set_target_properties(stipple_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(stipple_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stipple_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(stipple_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stipple_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME stipple COMMAND stipple_tests)

add_executable(lic_tests
  tests/lic_tests.cpp
  src/lic.cpp
  src/luminance.cpp
  src/optical_flow.cpp
  src/structure_edges.cpp
  src/structure_sampling.cpp
)
target_include_directories(lic_tests PRIVATE src)
target_compile_features(lic_tests PRIVATE cxx_std_20)
set_target_properties(lic_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(lic_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(lic_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(lic_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(lic_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME lic COMMAND lic_tests)

add_executable(posterize_tests
  tests/posterize_tests.cpp
  src/luminance.cpp
  src/posterize.cpp
)
target_include_directories(posterize_tests PRIVATE src)
target_compile_features(posterize_tests PRIVATE cxx_std_20)
set_target_properties(posterize_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(posterize_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(posterize_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(posterize_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(posterize_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME posterize COMMAND posterize_tests)

add_executable(graph_yaml_tests
  tests/graph_yaml_tests.cpp
  src/graph_yaml.cpp
)
target_include_directories(graph_yaml_tests PRIVATE src)
target_compile_features(graph_yaml_tests PRIVATE cxx_std_20)
set_target_properties(graph_yaml_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(graph_yaml_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graph_yaml_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(graph_yaml_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graph_yaml_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME graph_yaml COMMAND graph_yaml_tests)

add_executable(scene_source_tests
  tests/scene_source_tests.cpp
  src/scene_source.cpp
)
target_include_directories(scene_source_tests PRIVATE src)
target_compile_features(scene_source_tests PRIVATE cxx_std_20)
set_target_properties(scene_source_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(scene_source_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(scene_source_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(scene_source_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(scene_source_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME scene_source COMMAND scene_source_tests)

add_executable(optical_flow_tests
  tests/optical_flow_tests.cpp
  src/optical_flow.cpp
)
target_include_directories(optical_flow_tests PRIVATE src)
target_compile_features(optical_flow_tests PRIVATE cxx_std_20)
set_target_properties(optical_flow_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(optical_flow_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(optical_flow_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(optical_flow_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(optical_flow_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME optical_flow COMMAND optical_flow_tests)

add_executable(hysteresis_tests
  tests/hysteresis_tests.cpp
  src/hysteresis.cpp
)
target_include_directories(hysteresis_tests PRIVATE src)
target_compile_features(hysteresis_tests PRIVATE cxx_std_20)
set_target_properties(hysteresis_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(hysteresis_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(hysteresis_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(hysteresis_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(hysteresis_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME hysteresis COMMAND hysteresis_tests)

add_executable(warp_history_tests
  tests/warp_history_tests.cpp
  src/optical_flow.cpp
  src/warp_history.cpp
)
target_include_directories(warp_history_tests PRIVATE src)
target_compile_features(warp_history_tests PRIVATE cxx_std_20)
set_target_properties(warp_history_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(warp_history_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(warp_history_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(warp_history_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(warp_history_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME warp_history COMMAND warp_history_tests)

add_executable(raster_compose_tests
  tests/raster_compose_tests.cpp
  src/color_dither.cpp
  src/color_mode.cpp
  src/color_quantization.cpp
  src/glyph_font.cpp
  src/raster_compose.cpp
)
target_include_directories(raster_compose_tests PRIVATE src)
target_compile_features(raster_compose_tests PRIVATE cxx_std_20)
set_target_properties(raster_compose_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(raster_compose_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(raster_compose_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(raster_compose_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(raster_compose_tests PRIVATE -Werror)
  endif()
endif()
target_link_libraries(raster_compose_tests PRIVATE PkgConfig::FREETYPE)
add_test(NAME raster_compose COMMAND raster_compose_tests)

add_executable(kitty_graphics_tests
  tests/kitty_graphics_tests.cpp
  src/base64.cpp
  src/kitty_graphics.cpp
)
target_include_directories(kitty_graphics_tests PRIVATE src)
target_compile_features(kitty_graphics_tests PRIVATE cxx_std_20)
set_target_properties(kitty_graphics_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(kitty_graphics_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kitty_graphics_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(kitty_graphics_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(kitty_graphics_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME kitty_graphics COMMAND kitty_graphics_tests)

add_executable(iterm_inline_tests
  tests/iterm_inline_tests.cpp
  src/base64.cpp
  src/iterm_inline.cpp
  src/png_writer.cpp
)
target_include_directories(iterm_inline_tests PRIVATE src)
target_compile_features(iterm_inline_tests PRIVATE cxx_std_20)
set_target_properties(iterm_inline_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(iterm_inline_tests PRIVATE ZLIB::ZLIB)
if(MSVC)
  target_compile_options(iterm_inline_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(iterm_inline_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(iterm_inline_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(iterm_inline_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME iterm_inline COMMAND iterm_inline_tests)

add_executable(render_mode_tests
  tests/render_mode_tests.cpp
  src/render_mode.cpp
)
target_include_directories(render_mode_tests PRIVATE src)
target_compile_features(render_mode_tests PRIVATE cxx_std_20)
set_target_properties(render_mode_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(render_mode_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_mode_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(render_mode_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(render_mode_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME render_mode COMMAND render_mode_tests)

add_executable(bandwidth_guard_tests
  tests/bandwidth_guard_tests.cpp
  src/bandwidth_guard.cpp
)
target_include_directories(bandwidth_guard_tests PRIVATE src)
target_compile_features(bandwidth_guard_tests PRIVATE cxx_std_20)
set_target_properties(bandwidth_guard_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(bandwidth_guard_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(bandwidth_guard_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(bandwidth_guard_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(bandwidth_guard_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME bandwidth_guard COMMAND bandwidth_guard_tests)

add_executable(graphics_alignment_tests
  tests/graphics_alignment_tests.cpp
  src/graphics_alignment.cpp
)
target_include_directories(graphics_alignment_tests PRIVATE src)
target_compile_features(graphics_alignment_tests PRIVATE cxx_std_20)
set_target_properties(graphics_alignment_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(graphics_alignment_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graphics_alignment_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(graphics_alignment_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graphics_alignment_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME graphics_alignment COMMAND graphics_alignment_tests)

add_executable(overlay_compose_tests
  tests/overlay_compose_tests.cpp
  src/overlay_compose.cpp
)
target_include_directories(overlay_compose_tests PRIVATE src)
target_compile_features(overlay_compose_tests PRIVATE cxx_std_20)
set_target_properties(overlay_compose_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(overlay_compose_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(overlay_compose_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(overlay_compose_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(overlay_compose_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME overlay_compose COMMAND overlay_compose_tests)

add_executable(hybrid_emitter_tests
  tests/hybrid_emitter_tests.cpp
  src/ansi.cpp
  src/base64.cpp
  src/color_dither.cpp
  src/color_quantization.cpp
  src/glyph_font.cpp
  src/graphics_alignment.cpp
  src/graphics_emitter.cpp
  src/hybrid_emitter.cpp
  src/iterm_inline.cpp
  src/kitty_graphics.cpp
  src/png_writer.cpp
  src/raster_compose.cpp
  src/render_layout.cpp
  src/render_mode.cpp
)
target_include_directories(hybrid_emitter_tests PRIVATE src)
target_include_directories(hybrid_emitter_tests SYSTEM PRIVATE third_party)
target_compile_features(hybrid_emitter_tests PRIVATE cxx_std_20)
set_target_properties(hybrid_emitter_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(hybrid_emitter_tests PRIVATE PkgConfig::FREETYPE ZLIB::ZLIB)
if(MSVC)
  target_compile_options(hybrid_emitter_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(hybrid_emitter_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(hybrid_emitter_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(hybrid_emitter_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME hybrid_emitter COMMAND hybrid_emitter_tests)

add_executable(graphics_emitter_tests
  tests/graphics_emitter_tests.cpp
  src/base64.cpp
  src/color_dither.cpp
  src/color_mode.cpp
  src/color_quantization.cpp
  src/glyph_font.cpp
  src/graphics_alignment.cpp
  src/graphics_emitter.cpp
  src/iterm_inline.cpp
  src/kitty_graphics.cpp
  src/png_writer.cpp
  src/raster_compose.cpp
  src/render_mode.cpp
)
target_include_directories(graphics_emitter_tests PRIVATE src)
target_compile_features(graphics_emitter_tests PRIVATE cxx_std_20)
set_target_properties(graphics_emitter_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(graphics_emitter_tests PRIVATE PkgConfig::FREETYPE ZLIB::ZLIB)
if(MSVC)
  target_compile_options(graphics_emitter_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graphics_emitter_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(graphics_emitter_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(graphics_emitter_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME graphics_emitter COMMAND graphics_emitter_tests)

add_executable(image_grid_tests
  tests/image_grid_tests.cpp
  src/image_grid.cpp
)
target_include_directories(image_grid_tests PRIVATE src)
target_compile_features(image_grid_tests PRIVATE cxx_std_20)
set_target_properties(image_grid_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(image_grid_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(image_grid_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(image_grid_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(image_grid_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME image_grid COMMAND image_grid_tests)

add_executable(stdin_data_tests
  tests/stdin_data_tests.cpp
  src/stdin_data.cpp
)
target_include_directories(stdin_data_tests PRIVATE src)
target_compile_features(stdin_data_tests PRIVATE cxx_std_20)
set_target_properties(stdin_data_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(stdin_data_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stdin_data_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(stdin_data_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stdin_data_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME stdin_data COMMAND stdin_data_tests)

add_executable(asciinema_in_tests
  tests/asciinema_in_tests.cpp
  src/asciinema_in.cpp
)
target_include_directories(asciinema_in_tests PRIVATE src)
target_compile_features(asciinema_in_tests PRIVATE cxx_std_20)
set_target_properties(asciinema_in_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(asciinema_in_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_in_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(asciinema_in_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_in_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME asciinema_in COMMAND asciinema_in_tests)

add_executable(asciinema_vte_tests
  tests/asciinema_vte_tests.cpp
  src/asciinema_vte.cpp
  src/color_quantization.cpp
)
target_include_directories(asciinema_vte_tests PRIVATE src)
target_compile_features(asciinema_vte_tests PRIVATE cxx_std_20)
set_target_properties(asciinema_vte_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(asciinema_vte_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_vte_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(asciinema_vte_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_vte_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME asciinema_vte COMMAND asciinema_vte_tests)

add_executable(asciinema_source_tests
  tests/asciinema_source_tests.cpp
  src/asciinema_source.cpp
  src/asciinema_in.cpp
  src/asciinema_vte.cpp
  src/color_quantization.cpp
)
target_include_directories(asciinema_source_tests PRIVATE src)
target_compile_features(asciinema_source_tests PRIVATE cxx_std_20)
set_target_properties(asciinema_source_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(asciinema_source_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_source_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(asciinema_source_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(asciinema_source_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME asciinema_source COMMAND asciinema_source_tests)

add_executable(video_decoder_tests
  tests/video_decoder_tests.cpp
  src/video_decoder.cpp
  src/media_input.cpp
  src/terminal.cpp
)
target_include_directories(video_decoder_tests PRIVATE src)
target_compile_features(video_decoder_tests PRIVATE cxx_std_20)
set_target_properties(video_decoder_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(video_decoder_tests PRIVATE PkgConfig::FFMPEG)
if(MSVC)
  target_compile_options(video_decoder_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(video_decoder_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(video_decoder_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(video_decoder_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME video_decoder COMMAND video_decoder_tests)

add_executable(caption_summarise_tests
  tests/caption_summarise_tests.cpp
  src/captions.cpp
)
target_include_directories(caption_summarise_tests PRIVATE src)
target_compile_features(caption_summarise_tests PRIVATE cxx_std_20)
set_target_properties(caption_summarise_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(caption_summarise_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(caption_summarise_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(caption_summarise_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(caption_summarise_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME caption_summarise COMMAND caption_summarise_tests)

add_executable(media_input_tests
  tests/media_input_tests.cpp
  src/media_input.cpp
)
target_include_directories(media_input_tests PRIVATE src)
target_compile_features(media_input_tests PRIVATE cxx_std_20)
set_target_properties(media_input_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(media_input_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(media_input_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(media_input_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(media_input_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME media_input COMMAND media_input_tests)

add_executable(stream_resolver_tests
  tests/stream_resolver_tests.cpp
  src/stream_resolver.cpp
)
target_include_directories(stream_resolver_tests PRIVATE src)
target_compile_features(stream_resolver_tests PRIVATE cxx_std_20)
set_target_properties(stream_resolver_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(stream_resolver_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stream_resolver_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(stream_resolver_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(stream_resolver_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME stream_resolver COMMAND stream_resolver_tests)

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
  src/color_dither.cpp
  src/color_mode.cpp
  src/color_quantization.cpp
  src/diff_emitter.cpp
  src/luminance.cpp
  src/posterize.cpp
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

add_executable(structure_sampling_tests
  tests/structure_sampling_tests.cpp
  src/luminance.cpp
  src/structure_sampling.cpp
)
target_include_directories(structure_sampling_tests PRIVATE src)
target_compile_features(structure_sampling_tests PRIVATE cxx_std_20)
set_target_properties(structure_sampling_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(structure_sampling_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(structure_sampling_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(structure_sampling_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(structure_sampling_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME structure_sampling COMMAND structure_sampling_tests)

add_executable(structure_edges_tests
  tests/structure_edges_tests.cpp
  ${CONTOURTTY_GPU_SOBEL_SOURCE}
  src/glyph_font.cpp
  src/glyph_shape.cpp
  src/luminance.cpp
  src/structure_edges.cpp
  src/structure_sampling.cpp
)
target_include_directories(structure_edges_tests PRIVATE src)
target_compile_features(structure_edges_tests PRIVATE cxx_std_20)
set_target_properties(structure_edges_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(structure_edges_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(structure_edges_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(structure_edges_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(structure_edges_tests PRIVATE -Werror)
  endif()
endif()
if(CONTOURTTY_GPU_LIBS)
  target_link_libraries(structure_edges_tests PRIVATE ${CONTOURTTY_GPU_LIBS})
endif()
target_link_libraries(structure_edges_tests PRIVATE PkgConfig::FREETYPE)
add_test(NAME structure_edges COMMAND structure_edges_tests)

add_executable(line_ligatures_tests
  tests/line_ligatures_tests.cpp
  src/line_ligatures.cpp
)
target_include_directories(line_ligatures_tests PRIVATE src)
target_compile_features(line_ligatures_tests PRIVATE cxx_std_20)
set_target_properties(line_ligatures_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(line_ligatures_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(line_ligatures_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(line_ligatures_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(line_ligatures_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME line_ligatures COMMAND line_ligatures_tests)

add_executable(terminal_tests
  tests/terminal_tests.cpp
  src/terminal.cpp
)
target_include_directories(terminal_tests PRIVATE src)
target_compile_features(terminal_tests PRIVATE cxx_std_20)
set_target_properties(terminal_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(terminal_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(terminal_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(terminal_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(terminal_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME terminal COMMAND terminal_tests)

add_executable(terminal_caps_tests
  tests/terminal_caps_tests.cpp
  src/terminal_caps.cpp
)
target_include_directories(terminal_caps_tests PRIVATE src)
target_compile_features(terminal_caps_tests PRIVATE cxx_std_20)
set_target_properties(terminal_caps_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(terminal_caps_tests PRIVATE PkgConfig::FREETYPE)
if(MSVC)
  target_compile_options(terminal_caps_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(terminal_caps_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(terminal_caps_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(terminal_caps_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME terminal_caps COMMAND terminal_caps_tests)

add_executable(auto_mode_tests
  tests/auto_mode_tests.cpp
  src/auto_mode.cpp
  src/structure_overlay.cpp
)
target_include_directories(auto_mode_tests PRIVATE src)
target_compile_features(auto_mode_tests PRIVATE cxx_std_20)
set_target_properties(auto_mode_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
if(MSVC)
  target_compile_options(auto_mode_tests PRIVATE /W4)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(auto_mode_tests PRIVATE /WX)
  endif()
else()
  target_compile_options(auto_mode_tests PRIVATE -Wall -Wextra -Wpedantic)
  if(CONTOURTTY_WARNINGS_AS_ERRORS)
    target_compile_options(auto_mode_tests PRIVATE -Werror)
  endif()
endif()
add_test(NAME auto_mode COMMAND auto_mode_tests)

find_program(BASH_EXECUTABLE bash)
if(BASH_EXECUTABLE)
  add_test(NAME input_keys_smoke
    COMMAND ${BASH_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/tests/input_keys_smoke.sh" $<TARGET_FILE:contourtty>
  )
  set_tests_properties(input_keys_smoke PROPERTIES SKIP_RETURN_CODE 77)
  add_test(NAME evolve_charset
    COMMAND ${BASH_EXECUTABLE} -c "$<TARGET_FILE:evolve_charset> --seed 1337 --name portrait-30 --output '${CMAKE_CURRENT_BINARY_DIR}/portrait-30.generated.json' && '${CMAKE_COMMAND}' -E compare_files '${CMAKE_CURRENT_SOURCE_DIR}/share/contourtty/charsets/portrait-30.json' '${CMAKE_CURRENT_BINARY_DIR}/portrait-30.generated.json'"
  )
endif()

set(CPACK_PACKAGE_NAME "contourtty")
set(CPACK_PACKAGE_VENDOR "contourtty")
set(CPACK_PACKAGE_CONTACT "https://github.com/gongahkia/strok")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Structure-aware ASCII terminal media renderer")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/gongahkia/strok")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_GENERATOR "TGZ")
if(UNIX AND NOT APPLE)
  list(APPEND CPACK_GENERATOR "DEB")
  set(CPACK_DEBIAN_PACKAGE_MAINTAINER "contourtty maintainers")
  set(CPACK_DEBIAN_PACKAGE_SECTION "video")
  set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
endif()
include(CPack)
