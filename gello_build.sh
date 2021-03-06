#!/bin/bash
#
#  Copyright (C) 2016 The CyanogenMod Project
#  Copyright (C) 2017 The LineageOS Project
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  Integrated SWE Build System for Gello
#

TOP_GELLO=$(pwd)


##
# Flag Booleans
#
FAST=false
NOSYNC=false
CLEAN=false
LOCAL=false

##
# Sync
#
function sync() {
    # If we have previously downloaded depot tools using this script
    # export its path for us
    if [ -d "$TOP_GELLO/depot/depot_tools" ]; then
        export PATH=$PATH:$TOP_GELLO/depot/depot_tools
    fi

    if [ "$CLEAN" == true ]; then
        cd $TOP_GELLO/env

        echo "Cleaning..."

        # Clean out stuffs
        rm -rf $SRC_GELLO/out
        find $TOP_GELLO -name index.lock -exec rm {} \;
        gclient recurse git clean -fdx .
    fi
    
    if [ -d "$TOP_GELLO/env/swe/channels/lineage" ]; then
        rm -rf $TOP_GELLO/env/swe/channels/lineage
    fi

    if [ "$NOSYNC" != true ]; then
        cd $TOP_GELLO/env

        echo "Syncing now!"
        GYP_CHROMIUM_NO_ACTION=1 gclient sync -n --no-nag-max
        local SYNCRET=$?

        cd swe/channels
        git clone https://github.com/LineageOS/gello_channel lineage

        if [ "$CLEAN" == true ] && [ "$SYNCRET" == 0 ]; then
            gclient recurse git clean -fdx .
            return $?
        else
            return $SYNCRET
        fi
    else
        return 0
    fi
}


##
# Setup
#
function setup() {
    local DONE_FILE=$TOP_GELLO/.cm_done
    local GOOGLE_SDK=$SRC_GELLO/third_party/android_tools/sdk/extras/google/google_play_services

    cd $SRC_GELLO

    if [ ! -f $DONE_FILE ]; then
        touch $DONE_FILE
    fi

    # If we don't have Google SDKs, get them
    # !! This asks a manual input to accept licenses !!
    if [ ! -d $GOOGLE_SDK ]; then
        bash $SRC_GELLO/build/install-android-sdks.sh
    fi

    . build/android/envsetup.sh

    if [ "$FAST" != true ] && [ -f $DONE_FILE ]; then
        GYP_CHROMIUM_NO_ACTION=1 gn gen out/Release --args='swe_channels="lineage" target_os="android" is_debug=false symbol_level=0'
        return $?
    else
        return 0
    fi
}


##
# Compile
#
function compile() {
    local TMP_APK=$SRC_GELLO/out/Release/apks/SWE_AndroidBrowser.apk
    local OUT_TARGET=$TOP_GELLO/Gello.apk

    cd $SRC_GELLO

    # Gello "shell" builds only if we have GELLO_SRC == true ,
    # because we just wait it to build from here
    GELLO_SRC=true

    # Make things
    ninja -C out/Release swe_android_browser_apk
    local BUILDRET=$?

    if [ "$LOCAL" == true ]; then
        rm -rf $BUILD_GELLO
        mv $BACKUP_GELLO $BUILD_GELLO
    fi

    export GELLO_SRC=false

    if [ "$BUILDRET" == 0 ]; then
        if [ -f "$OUT_TARGET" ]; then
            rm -f $OUT_TARGET
        fi
        cp $TMP_APK $OUT_TARGET
        return $?
    else
        return $?
    fi
}


##
# Check Flags
#
function parseflags() {
    for flag in "$@"
    do
        case "$flag" in
            --fast)
                NOSYNC=true
                FAST=true
                ;;
            --no-sync)
                NOSYNC=true
                ;;
            --clean)
                CLEAN=true
                ;;
        esac
    done
}


##
# PathValidator
#
function pathvalidator() {
    local ENV_PATH=$TOP_GELLO/external/gello-build

    # Adjust path to make sure it works both from make and manual sh execution
    if [ ! -d "$TOP_GELLO/env/src" ]; then
        if [ -d "$ENV_PATH" ]; then
            TOP_GELLO=$ENV_PATH
        fi
    fi

    # Set up paths now
    SRC_GELLO=$TOP_GELLO/env/src
    BACKUP_GELLO=$SRC_GELLO/swe/browser_orig
    BUILD_GELLO=$SRC_GELLO/swe/browser
    READY_APK=$TOP_GELLO/Gello.apk
}


##
# Help
#
function helpgello() {
    cat<<EOF
Gello inline build system (c) CyanogenMod 2016
                          (c) LineageOS 2017
Usage: ./gello_build.sh <flags>
flags:
    --clean       = Make a clean build
    --depot       = Install Depot Tool
    --fast        = Skip sync and runhooks, useful for testing local changes
    --no-sync     = Skip sync
EOF
}


##
# Depot
#
function getdepot() {
    cd $TOP_GELLO

    mkdir depot
    cd depot
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
}


##
# Main
#
pathvalidator

if [ "$1" == "--depot" ]; then
    getdepot && exit 0
elif [ "$1" == "--help" ]; then
    helpgello && exit 0
fi

parseflags "$@"

sync && setup && compile

if [ "$?" == 0 ]; then
    echo "$(tput setaf 2)Done! Gello: $READY_APK$(tput sgr reset)"
    exit 0
fi
