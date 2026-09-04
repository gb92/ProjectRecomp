cmake_minimum_required(VERSION 3.20)
project(xex_dump)

set(CMAKE_CXX_STANDARD 17)

set(XENON_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/XenonRecomp")
set(XENONUTILS_ROOT "${XENON_ROOT}/XenonUtils")
set(THIRDPARTY_ROOT "${XENON_ROOT}/thirdparty")

add_executable(xex_dump main.cpp)

target_sources(xex_dump PRIVATE
    ${XENONUTILS_ROOT}/xex.cpp
    ${XENONUTILS_ROOT}/image.cpp
    ${XENONUTILS_ROOT}/xex_patcher.cpp
    ${XENONUTILS_ROOT}/xdbf_wrapper.cpp
    ${XENONUTILS_ROOT}/memory_mapped_file.cpp
    ${THIRDPARTY_ROOT}/libmspack/libmspack/mspack/lzxd.c
    ${THIRDPARTY_ROOT}/libmspack/libmspack/mspack/system.c
    ${THIRDPARTY_ROOT}/tiny-AES-c/aes.c
)

target_include_directories(xex_dump PRIVATE
    ${XENONUTILS_ROOT}
    ${THIRDPARTY_ROOT}/libmspack/libmspack/mspack
    ${THIRDPARTY_ROOT}/tiny-AES-c
    ${THIRDPARTY_ROOT}/xxHash
    ${THIRDPARTY_ROOT}/TinySHA1
)

target_compile_definitions(xex_dump PRIVATE XXH_INLINE_ALL)

if(WIN32)
    target_compile_definitions(xex_dump PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN _CRT_SECURE_NO_WARNINGS)
endif()
