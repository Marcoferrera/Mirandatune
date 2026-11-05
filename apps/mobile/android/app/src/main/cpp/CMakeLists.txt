cmake_minimum_required(VERSION 3.10.2)

project(dsp_engine)

# ✅ NOME CORRIGIDO (apenas um .cpp)
add_library(dsp_engine SHARED dsp_engine.cpp)

target_link_libraries(dsp_engine
    android
    log)