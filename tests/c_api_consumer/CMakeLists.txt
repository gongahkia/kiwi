cmake_minimum_required(VERSION 3.20)

project(strok_c_api_consumer LANGUAGES C)

find_package(strok CONFIG REQUIRED)

add_executable(strok_c_api_consumer main.c)
target_compile_features(strok_c_api_consumer PRIVATE c_std_11)
set_target_properties(strok_c_api_consumer PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
  C_EXTENSIONS OFF
)
target_link_libraries(strok_c_api_consumer PRIVATE strok::c_api)

enable_testing()
add_test(NAME strok_c_api_consumer COMMAND strok_c_api_consumer)
