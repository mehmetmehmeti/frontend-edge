cmake_minimum_required(VERSION 3.16)

project(DiplomaFrontendEdge VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(BZip2 REQUIRED)
find_package(EXPAT REQUIRED)
find_package(Fontconfig REQUIRED)
find_package(PNG REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml)

qt_standard_project_setup()

qt_add_executable(appDiplomaFrontendEdge
    main.cpp
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
        Fontconfig::Fontconfig
        freetype
        EXPAT::EXPAT
)

include(GNUInstallDirs)
install(TARGETS appDiplomaFrontendEdge
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
