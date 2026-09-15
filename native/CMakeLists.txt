cmake_minimum_required(VERSION 3.25)
project(QuietDawnNative LANGUAGES CXX)
if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Use the x64 MSVC Release toolchain.")
endif()
set(UE4SS_SDK "" CACHE PATH "RE-UE4SS checkout at 97b7e501c")
find_package(Git REQUIRED)
foreach(item IN ITEMS ".;97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1" "deps/first/Unreal;eb40a05f49509bdeb1ac39287032b60af585cca8")
    list(GET item 0 folder)
    list(GET item 1 expected)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${UE4SS_SDK}/${folder}" rev-parse HEAD
        OUTPUT_VARIABLE actual OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE result)
    if(NOT result EQUAL 0 OR NOT actual STREQUAL expected)
        message(FATAL_ERROR "Incorrect SDK revision for ${folder}; see BUILD.md.")
    endif()
endforeach()
include(FetchContent)
# Header dependencies of the public SDK; none of their libraries is built.
FetchContent_Declare(fmt GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG 40626af88bd7df9a5fb80be7b25ac85b122d6c21 SOURCE_SUBDIR headers_only)
FetchContent_Declare(imgui GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG 5d4126876bc10396d4c6511853ff10964414c776 SOURCE_SUBDIR headers_only)
FetchContent_Declare(textedit GIT_REPOSITORY https://github.com/UE4SS-RE/ImGuiColorTextEdit.git
    GIT_TAG 6d943aba9f7cef05da80b86dbb0253b63818f95c SOURCE_SUBDIR headers_only)
FetchContent_Declare(zydis GIT_REPOSITORY https://github.com/zyantific/zydis.git
    GIT_TAG a2278f1d254e492f6a6b39f6cb5d1f5d515659dc GIT_SUBMODULES dependencies/zycore SOURCE_SUBDIR headers_only)
FetchContent_MakeAvailable(fmt imgui textedit zydis)
set(ZYCORE_INCLUDE "${zydis_SOURCE_DIR}/dependencies/zycore/include" CACHE PATH "Zycore headers pinned by Zydis")
file(GLOB first_includes LIST_DIRECTORIES true "${UE4SS_SDK}/deps/first/*/include")
add_library(QuietDawnNative SHARED main.cpp SprintPrompts.cpp SprintPrompts.hpp ClawAssets.cpp ClawAssets.hpp EventQueue.hpp ObjectIdentity.hpp)
set_target_properties(QuietDawnNative PROPERTIES OUTPUT_NAME main MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
target_compile_features(QuietDawnNative PRIVATE cxx_std_23)
target_compile_definitions(QuietDawnNative PRIVATE
    UNICODE _UNICODE NDEBUG UE_BUILD_SHIPPING UE_GAME PLATFORM_WINDOWS PLATFORM_MICROSOFT
    OVERRIDE_PLATFORM_HEADER_NAME=Windows UBT_COMPILED_PLATFORM=Win64
    _WIN32_WINNT=0x0A00 WINVER=0x0A00 FMT_HEADER_ONLY=1)
target_compile_options(QuietDawnNative PRIVATE /O2 /EHsc /utf-8 /Brepro)
target_include_directories(QuietDawnNative PRIVATE ${first_includes}
    "${UE4SS_SDK}/UE4SS/include" "${UE4SS_SDK}/deps/first/Unreal/generated_include"
    "${UE4SS_SDK}/deps/first/Unreal/include/Unreal" "${UE4SS_SDK}/deps/first/Unreal/include/Unreal/Core"
    "${fmt_SOURCE_DIR}/include" "${imgui_SOURCE_DIR}" "${textedit_SOURCE_DIR}"
    "${zydis_SOURCE_DIR}/include" "${ZYCORE_INCLUDE}")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/Framecore2b.lib"
    COMMAND "${CMAKE_AR}" /nologo /machine:x64 "/def:${CMAKE_CURRENT_SOURCE_DIR}/Framecore2b.def" "/out:${CMAKE_CURRENT_BINARY_DIR}/Framecore2b.lib"
    DEPENDS Framecore2b.def VERBATIM)
add_custom_target(FramecoreImports DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/Framecore2b.lib")
add_dependencies(QuietDawnNative FramecoreImports)
target_link_libraries(QuietDawnNative PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/Framecore2b.lib" bcrypt kernel32)
target_link_options(QuietDawnNative PRIVATE /Brepro /OPT:REF /OPT:ICF /MAP)
