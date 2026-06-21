cmake_minimum_required(VERSION 3.20)

project(contourtty VERSION 0.0.0 LANGUAGES CXX)

option(CONTOURTTY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

include(GNUInstallDirs)

set(CONTOURTTY_GPU_SOBEL_SOURCE src/gpu_sobel_stub.cpp)
set(CONTOURTTY_GPU_LIBS)
if(APPLE)
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
  src/braille_renderer.cpp
  src/cli.cpp
  src/color_dither.cpp
  src/color_mode.cpp
  src/color_quantization.cpp
  src/diff_emitter.cpp
  src/frame_sampling.cpp
  src/glyph_ramp.cpp
  src/glyph_shape.cpp
  ${CONTOURTTY_GPU_SOBEL_SOURCE}
  src/halfblock_renderer.cpp
  src/luminance.cpp
  src/log.cpp
  src/main.cpp
  src/media_input.cpp
  src/media_probe.cpp
  src/png_writer.cpp
  src/player.cpp
  src/render_graph.cpp
  src/render_layout.cpp
  src/renderer.cpp
  src/structure_edges.cpp
  src/structure_sampling.cpp
  src/stream_resolver.cpp
  src/terminal.cpp
  src/video_decoder.cpp
)
target_compile_features(contourtty PRIVATE cxx_std_20)
set_target_properties(contourtty PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_compile_definitions(contourtty PRIVATE CONTOURTTY_VERSION="${PROJECT_VERSION}")
target_link_libraries(contourtty PRIVATE PkgConfig::FFMPEG ZLIB::ZLIB contourtty_audio contourtty_audio_decode ${CONTOURTTY_GPU_LIBS})

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

add_executable(glyph_shape_tests
  tests/glyph_shape_tests.cpp
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
add_test(NAME glyph_shape COMMAND glyph_shape_tests)

add_executable(cli_tests
  tests/cli_tests.cpp
  src/cli.cpp
  src/glyph_ramp.cpp
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

add_executable(golden_frame_tests
  tests/golden_frame_tests.cpp
  src/braille_renderer.cpp
  src/frame_sampling.cpp
  src/glyph_ramp.cpp
  src/glyph_shape.cpp
  ${CONTOURTTY_GPU_SOBEL_SOURCE}
  src/halfblock_renderer.cpp
  src/luminance.cpp
  src/render_layout.cpp
  src/renderer.cpp
  src/structure_edges.cpp
  src/structure_sampling.cpp
)
target_include_directories(golden_frame_tests PRIVATE src)
target_compile_features(golden_frame_tests PRIVATE cxx_std_20)
set_target_properties(golden_frame_tests PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_link_libraries(golden_frame_tests PRIVATE Threads::Threads ${CONTOURTTY_GPU_LIBS})
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
add_test(NAME structure_edges COMMAND structure_edges_tests)

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
