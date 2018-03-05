#!/bin/bash
#
#  build.sh
#
#  Created by Thomas So on 11/22/17.
#
#  This script is used to build the underlying JAR, for publishers using Unity.
#
#  It takes in 3 arguments -
#    1. The path to the Android SDK JAR.
#    2. The path to the AppLovin SDK JAR.
#    3. The path to the AdMob SDK JAR.
#
#  Example Usage: ./build.sh {ANDROID_SDK_JAR} {APPLOVIN_SDK_JAR} {ADMOB_SDK_JAR}
#

# TODO: Automatically rename packages

# Input parameters check
if [ "$#" -lt 3 ]; then
    echo "Invalid number of parameters"
    exit 1
fi

# Assign parameters
ANDROID_SDK_JAR=$1
APPLOVIN_SDK_JAR=$2
ADMOB_SDK_JAR=$3

# Setup build folder
if [ ! -d "build" ]; then
	mkdir build
else
    rm -R build/*
fi

# Compile source files into build folder
javac -classpath \
    "${ANDROID_SDK_JAR}:${APPLOVIN_SDK_JAR}:${ADMOB_SDK_JAR}" \
    -source 1.7 \
    -target 1.7 \
    -d build \
    ../*.java

# Package compiled files into JAR
cd build
jar cvf ../applovin-admob-adapters.jar *
