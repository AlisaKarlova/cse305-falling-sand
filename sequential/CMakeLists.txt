cmake_minimum_required(VERSION 3.16)
project(sand_sim LANGUAGES CXX)

# C++17 — enough for everything we use, available on Salle info g++.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Default to Release. Benchmarks must NOT be run on a Debug build —
# we'd be measuring -O0 noise. If a developer wants Debug, they pass
# -DCMAKE_BUILD_TYPE=Debug explicitly.
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Warnings on, but no -Werror (we don't want a stray warning on a
# different g++ version on Salle info to break the build for the TAs).
add_compile_options(-Wall -Wextra -Wpedantic)

add_executable(sand_sim
    src/main.cpp
    src/grid.cpp
    src/simulation.cpp
)
target_include_directories(sand_sim PRIVATE include)
