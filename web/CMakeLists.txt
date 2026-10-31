cmake_minimum_required(VERSION 3.20)
project(strok_web LANGUAGES CXX)

if(NOT EMSCRIPTEN)
  message(FATAL_ERROR "Use emcmake cmake -S web -B build/web to build the browser renderer")
endif()

get_filename_component(STROK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
include("${STROK_ROOT}/cmake/StrokCoreSources.cmake")
list(TRANSFORM STROK_RENDERER_CORE_SOURCES PREPEND "${STROK_ROOT}/")

add_executable(strok_web
  ${STROK_RENDERER_CORE_SOURCES}
  "${STROK_ROOT}/src/gpu_sobel_stub.cpp"
  src/bridge.cpp
)
target_compile_features(strok_web PRIVATE cxx_std_20)
target_include_directories(strok_web PRIVATE "${STROK_ROOT}/include" "${STROK_ROOT}/src")
target_include_directories(strok_web SYSTEM PRIVATE "${STROK_ROOT}/third_party")
target_compile_options(strok_web PRIVATE -Wall -Wextra -Wpedantic -fexceptions --use-port=freetype)
target_compile_definitions(strok_web PRIVATE STROK_DATA_DIR="/strok")
target_link_options(strok_web PRIVATE
  --use-port=freetype
  -fexceptions
  -sMODULARIZE=1
  -sEXPORT_ES6=1
  -sEXPORT_NAME=createStrok
  -sENVIRONMENT=web,worker,node
  -sALLOW_MEMORY_GROWTH=1
  -sMAXIMUM_MEMORY=268435456
  -sSTACK_SIZE=1048576
  -sFILESYSTEM=1
  -sDISABLE_EXCEPTION_CATCHING=0
  "-sEXPORTED_FUNCTIONS=['_malloc','_free','_strok_web_create','_strok_web_destroy','_strok_web_reset','_strok_web_render','_strok_web_cells','_strok_web_cell_count','_strok_web_error']"
  "-sEXPORTED_RUNTIME_METHODS=['HEAPU8','HEAPU32','UTF8ToString']"
  --embed-file "${STROK_ROOT}/share/strok/noise@/strok/noise"
  --embed-file "${STROK_ROOT}/share/strok/charsets@/strok/charsets"
  --embed-file "${CMAKE_CURRENT_SOURCE_DIR}/assets/SourceCodePro-Regular.otf@/strok/font.otf"
)
set_target_properties(strok_web PROPERTIES
  OUTPUT_NAME strok
  SUFFIX .mjs
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/wasm"
)
