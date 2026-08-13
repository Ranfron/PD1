cmake_minimum_required(VERSION 3.22.1)
project(pdf_power_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp)
set(HAS_LLAMA_SRC FALSE)
if(EXISTS ${LLAMA_DIR}/CMakeLists.txt)
  set(HAS_LLAMA_SRC TRUE)
endif()

add_library(paddle_vl_stub SHARED paddle_vl_stub.cpp)

find_library(log-lib log)
find_library(android-lib android)

if(HAS_LLAMA_SRC)
  message(STATUS "llama.cpp found — enabling llama.cpp + MTMD + PaddleOCR-VL")

  # Keep the Android native build focused on the libraries needed by the app.
  set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_MTMD ON CACHE BOOL "" FORCE)
  set(MTMD_VIDEO OFF CACHE BOOL "" FORCE)
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

  add_subdirectory(${LLAMA_DIR} ${CMAKE_BINARY_DIR}/llama)

  target_include_directories(paddle_vl_stub PRIVATE
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
    ${LLAMA_DIR}/tools/mtmd
  )

  # LLAMA_BUILD_MTMD=ON with LLAMA_BUILD_TOOLS=OFF creates the public mtmd
  # library target. It contains the PaddleOCR projector implementation.
  target_link_libraries(paddle_vl_stub
    mtmd
    llama
    ${log-lib}
    ${android-lib}
  )
  target_compile_definitions(paddle_vl_stub PRIVATE HAS_LLAMA=1 HAS_MTMD=1)
else()
  message(STATUS "llama.cpp missing — GGUF validation/ML Kit fallback only")
  target_link_libraries(paddle_vl_stub ${log-lib} ${android-lib})
endif()
