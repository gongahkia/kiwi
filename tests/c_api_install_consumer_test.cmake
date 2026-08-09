if(NOT DEFINED STROK_BINARY_DIR OR NOT DEFINED STROK_INSTALL_PREFIX OR
   NOT DEFINED STROK_CONSUMER_SOURCE_DIR OR NOT DEFINED STROK_CONSUMER_BINARY_DIR)
  message(FATAL_ERROR "C ABI installed-consumer test requires all configured paths")
endif()

function(run_checked)
  execute_process(
    COMMAND ${ARGN}
    RESULT_VARIABLE status
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
  )
  if(NOT status EQUAL 0)
    string(JOIN " " command ${ARGN})
    message(FATAL_ERROR "${command} failed with status ${status}\n${stdout}${stderr}")
  endif()
endfunction()

run_checked("${CMAKE_COMMAND}" --install "${STROK_BINARY_DIR}" --prefix "${STROK_INSTALL_PREFIX}")
run_checked(
  "${CMAKE_COMMAND}"
  -S "${STROK_CONSUMER_SOURCE_DIR}"
  -B "${STROK_CONSUMER_BINARY_DIR}"
  "-DCMAKE_PREFIX_PATH=${STROK_INSTALL_PREFIX}"
)
run_checked("${CMAKE_COMMAND}" --build "${STROK_CONSUMER_BINARY_DIR}" --parallel)
run_checked("${CMAKE_CTEST_COMMAND}" --test-dir "${STROK_CONSUMER_BINARY_DIR}" --output-on-failure)
