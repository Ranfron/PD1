# Optional native build for PaddleOCR-VL / llama.cpp
# Stub only — does not link any heavy library by default.
# When you add llama.cpp sources, enable the library target below.

cmake_minimum_required(VERSION 3.18.1)
project(paddle_vl_stub)

# Placeholder static lib so Gradle externalNativeBuild succeeds if enabled.
add_library(paddle_vl_stub SHARED
    paddle_vl_stub.cpp
)

find_library(log-lib log)
target_link_libraries(paddle_vl_stub ${log-lib})
