cmake_minimum_required(VERSION 3.10.2)

# Define o nome da biblioteca final (libdsp_engine.so)
project(dsp_engine)

# ✅ APONTA PARA O NOVO ARQUIVO REAL
add_library(dsp_engine SHARED dsp_engine.cpp)

target_link_libraries(dsp_engine
    android
    log)