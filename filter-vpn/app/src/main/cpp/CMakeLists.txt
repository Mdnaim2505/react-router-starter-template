# Native tunnel engine for Filter VPN.
cmake_minimum_required(VERSION 3.22.1)
project(filtervpn C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(filtervpn SHARED
        native-lib.cpp)

target_compile_options(filtervpn PRIVATE -fvisibility=hidden)

find_library(log-lib log)
target_link_libraries(filtervpn ${log-lib})
