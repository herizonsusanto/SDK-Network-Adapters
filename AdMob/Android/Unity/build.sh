#!/bin/bash
#
#  build.sh
#
#  Created by Thomas So on 11/22/17.
#
#  This script is used to build the underlying JAR, for publishers using Unity.
#
#  It takes in 2 arguments -
#    1. The SDK version number
#    2. The output directory
#
#  Flags -
#    -o - Opens the output directory upon completion.
#
#  Example Usage: ./build.sh 4.2.0 /Users/thomasso/AppLovin/SDK-iOS/build/ -o
#

javac -classpath \
"/Users/thomasso/Downloads/applovin-sdk-7.5.0.jar:/Users/thomasso/Library/Android/sdk/platforms/android-25/android.jar:/Users/thomasso/.android/build-cache/3422b6b464c555dcab548a53f71e06fbcfe6e63b/output/jars/classes.jar:/Users/thomasso/Downloads/admob.jar" \
    -source 1.7 \
    -target 1.7 \
    ../*.java

jar cvf adapter.jar *
