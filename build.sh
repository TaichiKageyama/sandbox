#!/bin/bash -x
export TZ="JST-9"
export KERNEL="$1"
export ARCH="$2"
export DEFCONFIG="$3"
export TARGET="$4"
export TAG="$5"
export WORKDIR="$6"

[ "$ENV_KERNEL" != "" ] && export KERNEL="$ENV_KERNEL"
[ "$ENV_ARCH" != "" ] && export ARCH="$ENV_ARCH"
[ "$ENV_DEFCONFIG" != "" ] && export DEFCONFIG="$ENV_DEFCONFIG"
[ "$ENV_TARGET" != "" ] && export TARGET="$ENV_TARGET"
[ "$ENV_TAG" != "" ] && export TAG="$ENV_TAG"
[ "$ENV_WORKDIR" != "" ] && export WORKDIR="$ENV_WORKDIR"

export USE_CCACHE=1
export CCACHE_DIR=/CCACHE
mkdir -p $CCACHE_DIR
GO=0

exit_msg(){
        rt=$1 msg="$2"
        echo $msg
        exit $rt
}

# ARG CHECK
#--- 32bit: pi1, zero, zero-w, pi-cm1
[ "$ARCH" = "arm" ] && [ "$KERNEL" = "kernel" ] && [ "$DEFCONFIG" = "bcmrpi_defconfig" ] && GO=1
#---- 32bit: pi2, pi3, pi3+, zero2, zero2-w, pi-cm3, pi-cm3+
[ "$ARCH" = "arm" ] && [ "$KERNEL" = "kernel7" ] && [ "$DEFCONFIG" = "bcm2709_defconfig" ] && GO=1
#---- 32bit: pi4, pi400, pi-cm4 
[ "$ARCH" = "arm" ] && [ "$KERNEL" = "kernel7l" ] && [ "$DEFCONFIG" = "bcm2711_defconfig" ] && GO=1
#---- 64bit: pi3, pi3+, zero2-w, pi-cm3, pi-cm3+, pi-cm4
[ "$ARCH" = "arm64" ] && [ "$KERNEL" = "kernel8" ] && [ "$DEFCONFIG" = "bcm2711_defconfig" ] && GO=1

[ "$ARCH" = "arm" ] && export IMG=zImage
[ "$ARCH" = "arm64" ] && export IMG=Image

[ $GO -eq 0 ] && exit_msg "Args are invalid" 1

export NPROC=`nproc`
export SRC=/tmp/linux/

setup_cross_compiler()
{
        case `arch` in
        "x86_64"  )
                [ "$ARCH" = arm ] && export CROSS_COMPILE="ccache arm-linux-gnueabihf-"
                [ "$ARCH" = arm64 ] && export CROSS_COMPILE="ccache aarch64-linux-gnu-"
                [ "$ARCH" = amd64 ]  && export CC="ccache gcc"
                ;;
        "armv7l"  )
                [ "$ARCH" = arm ] && export CC="ccache gcc"
                [ "$ARCH" = arm64 ] && exit_msg 1 "Build for $ARCH is not supported on armv7l"
                [ "$ARCH" = amd64 ] && exit_msg 1 "Build for $ARCH is not supported on armv7l"
                ;;
        "aarch64" )
                [ "$ARCH" = arm ] && export CROSS_COMPILE="ccache arm-linux-gnueabihf-"
                [ "$ARCH" = arm64 ] && export CC="ccache gcc"
                [ "$ARCH" = amd64 ] && export CROSS_COMPILE="ccache x86_64-linux-gnu-"
                ;;
        esac
}

pre_build_kernel()
{
        local ret=1
        cd `dirname $SRC`
        git clone --depth=1 --branch $TARGET https://github.com/raspberrypi/linux
        cd $SRC
	make $DEFCONFIG
        ret=$?
	./scripts/config --enable BLK_DEV_RBD
        ./scripts/config --disable DEBUG_INFO
	#./scripts/config --set-str CONFIG_LOCALVERSION "-v8"
        #sed -i 's/.*CONFIG_BLK_DEV_RBD.*/CONFIG_BLK_DEV_RBD=m/g' .config
	sed -i "s/CONFIG_LOCALVERSION=\"\(.*\)\"/CONFIG_LOCALVERSION=\"\1-$TAG\"/" .config

        export KERNEL_VERS=`make kernelversion`
        export DATE=$(date +%Y%m%d-%H%M%S)
        export BOOT=/$WORKDIR/$KERNEL_VERS/$DATE/boot.$ARCH
        export ROOT=/$WORKDIR/$KERNEL_VERS/$DATE/root.$ARCH
        mkdir -p $ROOT
        git clone --depth=1 --branch $TARGET https://github.com/raspberrypi/firmware
        mkdir -p $BOOT
        mv firmware/boot/* $BOOT/.
        rm -rf firmware
        cd
        return $ret
}

build_kernel()
{
        local ret=1
        cd $SRC
	env | grep -e CROSS -e ARCH
        make -j $NPROC $IMG modules dtbs
        ret=$?
        return $ret
}

install_modules()
{
        local ret=1
        cd $SRC
        make INSTALL_MOD_PATH=$ROOT modules_install
        ret=$?
	export KERNEL_RELEASE_VERS=$(cat ./include/config/kernel.release)
        cd
        return $red
}

install_kernel()
{
        cd $SRC
        cp -f arch/$ARCH/boot/$IMG $BOOT/$IMG-${KERNEL_RELEASE_VERS}
        cp -f arch/$ARCH/boot/dts/*.dtb $BOOT/.
        cp -f arch/$ARCH/boot/dts/overlays/*.dtb* $BOOT/overlays/.
        cp -f arch/$ARCH/boot/dts/overlays/README $BOOT/overlays/.
        cd
        echo "Completed: arch: $ARCH target: $TARGET: kernel: $KERNEL_RELEASE_VERS"
}

setup_cross_compiler
pre_build_kernel && \
build_kernel && \
install_modules && \
install_kernel

