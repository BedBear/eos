#!/usr/bin/env bash
set -eo pipefail
. ./.cicd/helpers/general.sh

mkdir -p $BUILD_DIR

if [[ $(uname) == 'Darwin' ]]; then

    # You can't use chained commands in execute
    cd $BUILD_DIR
    [[ $TRAVIS == true ]] && ccache -s
    cmake ..
    make -j$JOBS

else # Linux

    MOUNTED_DIR='/workdir'
    ARGS=${ARGS:-"--rm -v $(pwd):$MOUNTED_DIR"}

    . $HELPERS_DIR/docker-hash.sh

    PRE_COMMANDS="cd $MOUNTED_DIR/build"
    # PRE_COMMANDS: Executed pre-cmake
    # CMAKE_EXTRAS: Executed within and right before the cmake path (cmake CMAKE_EXTRAS ..)
    if [[ $IMAGE_TAG == 'ubuntu-18.04' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++' -DCMAKE_C_COMPILER='clang'"
    elif [[ $IMAGE_TAG == 'ubuntu-16.04' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_TOOLCHAIN_FILE=$MOUNTED_DIR/.cicd/helpers/clang.make -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    elif [[ $IMAGE_TAG == 'centos-7.6' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && source /opt/rh/devtoolset-8/enable && source /opt/rh/rh-python36/enable && export PATH=/usr/lib64/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'amazonlinux-2' ]]; then
        PRE_COMMANDS="$PRE_COMMANDS && export PATH=/usr/lib64/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++' -DCMAKE_C_COMPILER='clang'"
    fi

    BUILD_COMMANDS="cmake $CMAKE_EXTRAS .. && make -j$JOBS"

    # Docker Commands
    if [[ $BUILDKITE == true ]]; then
        # Generate Base Images
        $CICD_DIR/generate-base-images.sh
        [[ $ENABLE_INSTALL == true ]] && COMMANDS="cp -r $MOUNTED_DIR ~/eosio && cd ~/eosio/build &&"
        COMMANDS="$COMMANDS $BUILD_COMMANDS"
        [[ $ENABLE_INSTALL == true ]] && COMMAND="$COMMAND && make install"
    elif [[ $TRAVIS == true ]]; then
        ARGS="$ARGS -v /usr/lib/ccache -v $HOME/.ccache:/opt/.ccache -e JOBS -e TRAVIS -e CCACHE_DIR=/opt/.ccache"
        COMMANDS="ccache -s && $BUILD_COMMANDS"
    fi

    COMMANDS="$PRE_COMMANDS && $COMMANDS"

    # Load BUILDKITE Environment Variables for use in docker run
    if [[ -f $BUILDKITE_ENV_FILE ]]; then
        evars=""
        while read -r var; do
            evars="$evars --env ${var%%=*}"
        done < "$BUILDKITE_ENV_FILE"
    fi

    eval docker run $ARGS $evars $FULL_TAG bash -c \"$COMMANDS\"

fi