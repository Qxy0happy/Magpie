cmake_minimum_required(VERSION 3.20)
project(magpie_vulkan_prototype LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL3 REQUIRED IMPORTED_TARGET sdl3)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0 gio-unix-2.0)
find_package(Threads REQUIRED)

set(DXC_EXECUTABLE "/tmp/dxc/bin/dxc" CACHE FILEPATH "path to the DXC executable")
set(SHADER_OUT "${CMAKE_BINARY_DIR}/bicubic.spv")

add_custom_command(
    OUTPUT "${SHADER_OUT}"
    COMMAND "${DXC_EXECUTABLE}" -T cs_6_0 -E main -spirv
            -fspv-target-env=vulkan1.0 -HV 2018
            -Fo "${SHADER_OUT}" "${CMAKE_SOURCE_DIR}/shaders/bicubic.hlsl"
    DEPENDS "${CMAKE_SOURCE_DIR}/shaders/bicubic.hlsl"
    COMMENT "Compiling bicubic.hlsl to SPIR-V with DXC"
    VERBATIM)

add_custom_target(shaders ALL DEPENDS "${SHADER_OUT}")

add_executable(magpie_vulkan_prototype
    src/main.cpp
    src/renderer.cpp
    src/portal_capture.cpp)

add_dependencies(magpie_vulkan_prototype shaders)
target_link_libraries(magpie_vulkan_prototype PRIVATE
    PkgConfig::SDL3
    PkgConfig::PIPEWIRE
    PkgConfig::GIO
    Threads::Threads)

add_custom_command(
    TARGET magpie_vulkan_prototype POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${SHADER_OUT}" "$<TARGET_FILE_DIR:magpie_vulkan_prototype>/bicubic.spv"
    COMMENT "Copying bicubic.spv next to the executable")
