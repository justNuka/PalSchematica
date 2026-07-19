cmake_minimum_required(VERSION 3.18)

set(TARGET PalSchematicaFilesystem)
project(${TARGET})

add_library(${TARGET} SHARED "dllmain.cpp")
target_include_directories(${TARGET} PRIVATE .)
target_link_libraries(${TARGET} PUBLIC UE4SS)

target_compile_features(${TARGET} PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(${TARGET} PRIVATE /W4 /permissive-)
endif()
