cmake_minimum_required(VERSION 3.16)
project(sand_sim LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)


if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()


add_compile_options(-Wall -Wextra -Wpedantic)
option(ENABLE_VIEWER "Build the interactive SDL2 viewer (requires SDL2)" OFF)

set(SAND_SIM_SOURCES
    src/main.cpp
    src/grid.cpp
    src/simulation.cpp
    src/margolus.cpp
)

if(ENABLE_VIEWER)
    list(APPEND SAND_SIM_SOURCES src/viewer.cpp)
endif()

add_executable(sand_sim ${SAND_SIM_SOURCES})
target_include_directories(sand_sim PRIVATE include)
find_package(Threads REQUIRED)
target_link_libraries(sand_sim PRIVATE Threads::Threads)

if(ENABLE_VIEWER)
    find_package(SDL2 REQUIRED)
    target_compile_definitions(sand_sim PRIVATE ENABLE_VIEWER=1)
    if(TARGET SDL2::SDL2)
        target_link_libraries(sand_sim PRIVATE SDL2::SDL2)
    else()
        # Fallback for older SDL2 CMake configs that don't export a target.
        target_include_directories(sand_sim PRIVATE ${SDL2_INCLUDE_DIRS})
        target_link_libraries(sand_sim PRIVATE ${SDL2_LIBRARIES})
    endif()
endif()