cmake_minimum_required(VERSION 3.16)

project(DiplomaFrontendEdge VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(BZip2 REQUIRED)
find_package(EXPAT REQUIRED)
find_package(Fontconfig REQUIRED)
find_package(PNG REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml QuickControls2)

qt_standard_project_setup()

qt_add_executable(appDiplomaFrontendEdge
    main.cpp
    core/streaming/StreamingBridgeRegistry.cpp
    core/streaming/StreamingBridgeRegistry.h
    core/streaming/VideoPreviewItem.cpp
    core/streaming/VideoPreviewItem.h
)

qt_add_qml_module(appDiplomaFrontendEdge
    URI DiplomaFrontendEdge
    VERSION 1.0
    QML_FILES
        Main.qml
)

target_link_libraries(appDiplomaFrontendEdge
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::Qml
        Qt6::QuickControls2
        Fontconfig::Fontconfig
        freetype
        EXPAT::EXPAT
)

target_include_directories(appDiplomaFrontendEdge
    PRIVATE
        core/streaming
)

get_target_property(EXPAT_ARCHIVE EXPAT::EXPAT IMPORTED_LOCATION_RELEASE)
if(NOT EXPAT_ARCHIVE)
    get_target_property(EXPAT_ARCHIVE EXPAT::EXPAT IMPORTED_LOCATION)
endif()
if(EXPAT_ARCHIVE)
    target_link_libraries(appDiplomaFrontendEdge
        PRIVATE
            -Wl,--whole-archive
            ${EXPAT_ARCHIVE}
            -Wl,--no-whole-archive
    )
endif()

include(GNUInstallDirs)
install(TARGETS appDiplomaFrontendEdge
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
