cmake_minimum_required(VERSION 3.21)
project(samaya-desktop VERSION 0.3.6 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets Svg Quick QuickControls2)

qt_add_executable(samaya-desktop WIN32
    src/main.cpp src/api.cpp src/api-local.cpp src/api.h src/control-channel.cpp src/desktop.cpp src/desktop.h src/legacy.cpp
)
qt_wrap_cpp(desktop_moc src/api.h src/desktop.h TARGET samaya-desktop)
target_sources(samaya-desktop PRIVATE ${desktop_moc})
qt_add_resources(samaya-desktop desktop_assets PREFIX / BASE assets FILES
    assets/alert.svg assets/arrow.svg assets/bell.svg assets/chevron.svg
    assets/copy.svg assets/menu.svg assets/model-lightning.svg assets/more.svg
    assets/speed-lightning-outline.svg
    assets/plus.svg assets/samaya-symbol.svg assets/search.svg assets/stop.svg
    assets/history.svg assets/inbox.svg assets/panels-top-left.svg assets/pin.svg assets/settings.svg
)
target_link_libraries(samaya-desktop PRIVATE Qt6::Widgets Qt6::Svg Qt6::Quick Qt6::QuickControls2)
target_compile_definitions(samaya-desktop PRIVATE SAMAYA_VERSION="${PROJECT_VERSION}")
if(MSVC)
    target_compile_options(samaya-desktop PRIVATE /utf-8 /W4 /permissive-)
endif()
if(WIN32)
    target_sources(samaya-desktop PRIVATE assets/windows.rc src/native-stdio.cpp src/native-stdio.h)
    target_include_directories(samaya-desktop PRIVATE assets)
    target_link_libraries(samaya-desktop PRIVATE dwmapi)
endif()
install(TARGETS samaya-desktop RUNTIME DESTINATION .)
install(FILES THIRD-PARTY.md DESTINATION .)

file(GLOB ui_sources CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/*.qml" "qml/*.js" "assets/upstream/*.svg")
qt_add_resources(samaya-desktop quick_ui PREFIX "/" FILES ${ui_sources} qml/qmldir packaging/legacy-0.2.sha256)
install(FILES assets/fonts/NotoSansSC.ttf DESTINATION fonts)
