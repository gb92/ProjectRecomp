cmake_minimum_required(VERSION 3.25)
project(thp8 VERSION 0.1.0 LANGUAGES CXX)

if(WIN32)
    enable_language(RC)
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/assets/mainmenu.bin"
    THP8_MAIN_MENU_HEX HEX)
string(LENGTH "${THP8_MAIN_MENU_HEX}" THP8_MAIN_MENU_HEX_LENGTH)
math(EXPR THP8_MAIN_MENU_SIZE "${THP8_MAIN_MENU_HEX_LENGTH} / 2")
string(REGEX REPLACE "(..)" "0x\\1, "
    THP8_MAIN_MENU_BYTES "${THP8_MAIN_MENU_HEX}")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/thp8_main_menu.in.h"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/thp8_main_menu.h"
    @ONLY
)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/assets/mainoptions.bin"
    THP8_MAIN_OPTIONS_HEX HEX)
string(LENGTH "${THP8_MAIN_OPTIONS_HEX}" THP8_MAIN_OPTIONS_HEX_LENGTH)
math(EXPR THP8_MAIN_OPTIONS_SIZE "${THP8_MAIN_OPTIONS_HEX_LENGTH} / 2")
string(REGEX REPLACE "(..)" "0x\\1, "
    THP8_MAIN_OPTIONS_BYTES "${THP8_MAIN_OPTIONS_HEX}")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/thp8_main_options.in.h"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/thp8_main_options.h"
    @ONLY
)

# Match the Windows and Linux architecture baseline used by ReXGlue.
add_compile_options(-march=x86-64-v2)
add_link_options(-march=x86-64-v2)

# Build the ReXGlue SDK from source (submodule at tools/rexglue-sdk)
set(REXGLUE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/rexglue-sdk")
set(REXGLUE_PATCH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../patches/rexglue-v0.10.0")
set(REXGLUE_EXPECTED_COMMIT "4c1350847bb2bbc5fbf4272c78731632fccce8ab")

find_package(Git REQUIRED)
execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${REXGLUE_SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE REXGLUE_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
if(NOT REXGLUE_COMMIT STREQUAL REXGLUE_EXPECTED_COMMIT)
    message(FATAL_ERROR
        "Expected ReXGlue ${REXGLUE_EXPECTED_COMMIT}, found ${REXGLUE_COMMIT}")
endif()

file(GLOB REXGLUE_PATCHES CONFIGURE_DEPENDS "${REXGLUE_PATCH_DIR}/*.patch")
if(NOT REXGLUE_PATCHES)
    message(FATAL_ERROR "No ReXGlue patches found in ${REXGLUE_PATCH_DIR}")
endif()
foreach(REXGLUE_PATCH IN LISTS REXGLUE_PATCHES)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REXGLUE_SOURCE_DIR}"
                apply --ignore-space-change --ignore-whitespace
                --check "${REXGLUE_PATCH}"
        RESULT_VARIABLE PATCH_CAN_APPLY
        OUTPUT_QUIET
        ERROR_QUIET
    )
    if(PATCH_CAN_APPLY EQUAL 0)
        message(STATUS "Applying ReXGlue patch: ${REXGLUE_PATCH}")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${REXGLUE_SOURCE_DIR}"
                    apply --ignore-space-change --ignore-whitespace
                    "${REXGLUE_PATCH}"
            COMMAND_ERROR_IS_FATAL ANY
        )
    else()
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${REXGLUE_SOURCE_DIR}"
                    apply --ignore-space-change --ignore-whitespace
                    --reverse --check "${REXGLUE_PATCH}"
            RESULT_VARIABLE PATCH_IS_APPLIED
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(NOT PATCH_IS_APPLIED EQUAL 0)
            message(FATAL_ERROR
                "ReXGlue patch conflicts with the SDK source: ${REXGLUE_PATCH}")
        endif()
    endif()
endforeach()

add_subdirectory("${REXGLUE_SOURCE_DIR}"
                 "${CMAKE_CURRENT_BINARY_DIR}/rexglue-sdk")

# Load generated source list.
set(GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../generated")
set(THP8_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../config/THP8_rexglue.toml")
if(NOT EXISTS "${GENERATED_DIR}/sources.cmake")
    message(FATAL_ERROR
        "Generated sources are missing. Run:\n"
        "  rexglue codegen "
        "${THP8_MANIFEST}")
endif()
include("${GENERATED_DIR}/sources.cmake")

add_executable(thp8 WIN32
    src/main.cpp
    src/thp8_app.cpp
    src/thp8_options_menu.cpp
    ${GENERATED_SOURCES}
)
target_include_directories(thp8 PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
    "${CMAKE_CURRENT_SOURCE_DIR}/../icons"
)
if(WIN32)
    target_sources(thp8 PRIVATE src/thp8.rc)
endif()

get_target_property(REXGLUE_RUNTIME_OUTPUT_DIRECTORY
    rexruntime RUNTIME_OUTPUT_DIRECTORY)
set_target_properties(thp8 PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${REXGLUE_RUNTIME_OUTPUT_DIRECTORY}"
)

target_include_directories(thp8 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${GENERATED_DIR}"
)

target_link_libraries(thp8 PRIVATE
    rex::runtime
    imgui::imgui
)

target_precompile_headers(thp8 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/thp8_pch.h"
)

# Apply SDK platform-specific configuration (entry point, whole-archive, etc.)
rexglue_configure_target(thp8 GPU_PLUGINS xenos)

# Allow project stubs to override SDK/generated symbols (linker level)
if(WIN32)
    target_link_options(thp8 PRIVATE "LINKER:/FORCE:MULTIPLE")
endif()

# Clang on Windows: suppress common recomp warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(thp8 PRIVATE
        -Wno-unused-variable
        -Wno-unused-but-set-variable
        -Wno-sign-compare
    )
endif()

if(WIN32)
    set(THP8_RUNTIME_FILES
        "$<TARGET_FILE:rexruntime>"
        "$<TARGET_FILE:rexgpu-xenos>"
    )
    if(REXGLUE_ENABLE_TRACY)
        list(APPEND THP8_RUNTIME_FILES "$<TARGET_FILE:TracyClient>")
    endif()

    install(TARGETS thp8
        RUNTIME DESTINATION .
        COMPONENT ProjectRecomp
    )
    install(FILES
        ${THP8_RUNTIME_FILES}
        DESTINATION .
        COMPONENT ProjectRecomp
    )

    file(TO_CMAKE_PATH "$ENV{VCToolsRedistDir}" THP8_VC_REDIST_ROOT)
    file(TO_CMAKE_PATH "$ENV{ProgramFiles}" THP8_PROGRAM_FILES)
    file(GLOB THP8_MSVC_RUNTIME_DIRS LIST_DIRECTORIES true
        "${THP8_VC_REDIST_ROOT}/x64/Microsoft.VC143.CRT"
        "${THP8_PROGRAM_FILES}/Microsoft Visual Studio/2022/*/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT"
    )
    list(SORT THP8_MSVC_RUNTIME_DIRS COMPARE NATURAL ORDER DESCENDING)
    if(NOT THP8_MSVC_RUNTIME_DIRS)
        message(FATAL_ERROR
            "Microsoft Visual C++ app-local runtime files were not found")
    endif()
    list(GET THP8_MSVC_RUNTIME_DIRS 0 THP8_MSVC_RUNTIME_DIR)
    set(THP8_MSVC_RUNTIME_FILES
        "${THP8_MSVC_RUNTIME_DIR}/msvcp140.dll"
        "${THP8_MSVC_RUNTIME_DIR}/msvcp140_atomic_wait.dll"
        "${THP8_MSVC_RUNTIME_DIR}/vcruntime140.dll"
        "${THP8_MSVC_RUNTIME_DIR}/vcruntime140_1.dll"
    )
    foreach(THP8_MSVC_RUNTIME_FILE IN LISTS THP8_MSVC_RUNTIME_FILES)
        if(NOT EXISTS "${THP8_MSVC_RUNTIME_FILE}")
            message(FATAL_ERROR
                "Required app-local runtime not found: "
                "${THP8_MSVC_RUNTIME_FILE}")
        endif()
    endforeach()
    install(FILES
        ${THP8_MSVC_RUNTIME_FILES}
        DESTINATION .
        COMPONENT ProjectRecomp
    )
    install(FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/../README.md"
        "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE"
        DESTINATION .
        COMPONENT ProjectRecomp
    )
    install(FILES
        "${REXGLUE_SOURCE_DIR}/LICENSE"
        DESTINATION .
        RENAME REXGLUE-LICENSE.txt
        COMPONENT ProjectRecomp
    )
endif()
