# =============================================================================
# Top-level ESP-IDF project CMake file
# Project: Project Auris — ESP32 firmware
#
# Build:    idf.py build
# Flash:    idf.py -p <PORT> flash
# Monitor:  idf.py -p <PORT> monitor
# =============================================================================
cmake_minimum_required(VERSION 3.16)

# Use the conventional IDF layout: main/ is the entry component, additional
# components live under components/. IDF auto-discovers both.
include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(auris)
