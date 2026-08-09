if(NOT DEFINED STROK_BINARY_DIR OR NOT DEFINED STROK_INSTALL_PREFIX OR
   NOT DEFINED STROK_CARGO_EXECUTABLE OR NOT DEFINED STROK_CARGO_MANIFEST OR
   NOT DEFINED STROK_CARGO_TARGET_DIR)
  message(FATAL_ERROR "Rust installed-binding test requires all configured paths")
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
  -E env
  "STROK_PREFIX=${STROK_INSTALL_PREFIX}"
  "CARGO_TARGET_DIR=${STROK_CARGO_TARGET_DIR}"
  "${STROK_CARGO_EXECUTABLE}"
  test
  --locked
  --manifest-path "${STROK_CARGO_MANIFEST}"
)
