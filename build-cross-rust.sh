#!/bin/bash

set -e

INSTALL_PREFIX=/usr/local/
BUILD_PREFIX=${PWD}
EABI=uclibcgnueabi
HOST=$(gcc -dumpmachine)

TARGET=armv5te-rcross-linux-${EABI}
CLEAN=0
TARGET_JSON=${TARGET}.json
LIBC=uclibc

RUST_BINARY_ARCHIVE_URL=https://static.rust-lang.org/dist/rust-nightly-x86_64-unknown-linux-gnu.tar.gz

# Parse args
for i in "$@"
do
    case $i in
	      --install-prefix=*)
	          INSTALL_PREFIX=$(readlink -f "${i#*=}")
	          shift
	          ;;
        --libc=*)
            LIBC=${i#*=}
            shift
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
	      *)
	          # unknown option
	          ;;
    esac
done

TOOLCHAIN_URL=${TOOLCHAIN_UCLIBC_URL}
TOOLCHAIN_GLIBC_URL=http://toolchains.free-electrons.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--glibc--bleeding-edge-2017.08-rc2-5-g5c1b185-1.tar.bz2
TOOLCHAIN_MUSL_URL=http://toolchains.free-electrons.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--musl--bleeding-edge-2017.08-rc2-5-g5c1b185-1.tar.bz2
TOOLCHAIN_UCLIBC_URL=http://toolchains.free-electrons.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--uclibc--bleeding-edge-2017.08-rc2-5-g5c1b185-1.tar.bz2

case ${LIBC} in
    glibc)
        TOOLCHAIN_URL=${TOOLCHAIN_GLIBC_URL}
        EABI=gnueabi
        ;;
    uclibc)
        TOOLCHAIN_URL=${TOOLCHAIN_UCLIBC_URL}
        EABI=uclibceabi
        ;;
    musl)
        TOOLCHAIN_URL=${TOOLCHAIN_MUSL_URL}
        EABI=musleabi
        ;;
    *)
        echo "I dont know toolchain for this libc"
        ;;
esac

TARGET=armv5te-rcross-linux-${EABI}
TARGET_JSON=${TARGET}.json
INSTALL_PATH=${INSTALL_PREFIX}/rust-${TARGET}/
CARGO_PREFIX=${INSTALL_PATH}cargo-armv5
TARGET_JSON_PATH=${INSTALL_PATH}/${TARGET_JSON}
RUST_BINARY_ARCHIVE_PATH=${BUILD_PREFIX}/$(basename ${RUST_BINARY_ARCHIVE_URL})
RUST_PATH=${INSTALL_PATH}/rust/
RUST_LIB=${RUST_PATH}/lib/rustlib
RUSTC=${RUST_PATH}/bin/rustc
CARGO=${RUST_PATH}/bin/cargo
OPT_LEVEL=${OPT_LEVEL:-"2"}
PANIC_STRATEGY=${PANIC_STRATEGY:-"abort"}
CARGO_HOME=${INSTALL_PATH}/cargo_home
PREINITED=0
THREADS=$(nproc)


echo "step 1 config variables"
echo "Install path: ${INSTALL_PATH}"
echo "Build prefix: ${BUILD_PREFIX}"
echo "Target EABI: ${EABI}"
echo "Host triplet: ${HOST}"

echo "step 2 Check current state to avoid double work"

echo "step 2.1 Check install path ${INSTALL_PATH}"
if [ ! -e ${INSTALL_PATH} ]; then
    echo "Install path not found, creating"
    mkdir ${INSTALL_PATH}
else
    echo "Clean up if requested so"
    if [ ${CLEAN} -eq 1 ]; then
        rm -rf ${INSTALL_PATH}/*
    fi
fi

if [ ${CLEAN} -eq 1 ]; then
    pushd ${BUILD_PREFIX}
    echo "step 2.2 Clean build prefix ${BUILD_PREFIX}"
    git clean -fd
    if [-e ${BUILD_PREFIX}/rust-git ]; then rm -rf ${BUILD_PREFIX}/rust-git; fi
    popd
fi

echo "step 3 Install cross-toolchain ${TOOLCHAIN_URL}"
pushd ${BUILD_PREFIX}
echo "step 3.1 Checking toolchain archive presence"
if [ ! -e $(basename ${TOOLCHAIN_URL}) ]; then
    echo "Downloading cross-toolchain archive ${TOOLCHAIN_URL}"
    wget ${TOOLCHAIN_URL}
else
    echo "Toolchain archive already obtained"
fi

TOOLCHAIN_PATH=${INSTALL_PATH}$(tar -tf $(basename ${TOOLCHAIN_URL}) | head -1 | cut -f1 -d"/")
LD=${TOOLCHAIN_PATH}/bin/arm-linux-ld LDFLAGS="-lgcc_eh -lgcc"
CC=${TOOLCHAIN_PATH}/bin/arm-linux-gcc
AR=${TOOLCHAIN_PATH}/bin/arm-linux-ar
popd

echo "step 3.2 Unpacking toolchain"
pushd ${INSTALL_PATH}
if [ ! -e ${TOOLCHAIN_PATH} ]; then
    echo "Unpacking toolchain ${BUILD_PREFIX}/$(basename ${TOOLCHAIN_URL}) to ${TOOLCHAIN_PATH}"
    tar xf ${BUILD_PREFIX}/$(basename ${TOOLCHAIN_URL})
else
    echo "Toolchain already unpacked"
fi
popd


echo "step 4 Install rust binaries"
pushd ${BUILD_PREFIX}
if [ ! -e ${RUST_PATH} ]; then
    if [ ! -e ${RUST_BINARY_ARCHIVE_PATH} ]; then
        echo "Downloading rust binaries ${RUST_BINARY_ARCHIVE_URL}"
        wget ${RUST_BINARY_ARCHIVE_URL}
    else
        echo "Rust binaries already obtained, skip downloading"
    fi
    tar xf ${RUST_BINARY_ARCHIVE_PATH}
    RUST_INSTALL_PATH=${BUILD_PREFIX}/$(tar -tf ${RUST_BINARY_ARCHIVE_PATH} | head -1 | cut -f1 -d"/")
    ${RUST_INSTALL_PATH}/install.sh --prefix=${RUST_PATH}
else
    echo "Rust binaries already installed, skip"
fi
popd
RUST_VERSION=$(${RUSTC} --version | cut -f2 -d'(' | cut -f1 -d' ')

echo "step 5 Install rust (libs) sources"
pushd ${BUILD_PREFIX}
if [ ! -e rust-git ]; then
    echo "Clone rust sources"
    git clone https://github.com/rust-lang/rust rust-git
else
    PREINITED=1
    echo "Rust sources already obtained, skip"
fi
popd

echo "step 6 Update cargo config"
pushd ${INSTALL_PATH}
echo "step 6.1 Check cargo home presence"
if [ ! -e ${CARGO_HOME} ]; then
    echo "Create ${CARGO_HOME}"
    mkdir ${CARGO_HOME}
else
    echo "Cargo home exists, skip"
fi

echo "step 6.2 Check cargo config presence"
if [ ! -e ${CARGO_HOME}/config ]; then
    echo "Create cargo config ${CARGO_HOME}/config"
    cat ${BUILD_PREFIX}/config | sed -e "s|linker = |linker = \"${INSTALL_PATH}/armv5-sysroot\"|" | sed -e "s|ar = |ar = \"${TOOLCHAIN_PATH}/bin/arm-linux-ar\"|" | sed -e "s|<eabi>|${EABI}|" > ${CARGO_HOME}/config
else
    echo "Cargo config exists, skip"
fi

echo "step 6.3 Check sysroot linker script presence"
if [ ! -e ${INSTALL_PATH}/armv5-sysroot ]; then
    echo "Create sysroot linker script"
    cat ${BUILD_PREFIX}/armv5-sysroot | sed -e "s|SYSROOT=|SYSROOT=${TOOLCHAIN_PATH}/arm-buildroot-linux-${EABI}/sysroot|" | sed -e "s|<gcc>|${TOOLCHAIN_PATH}/bin/arm-linux-gcc|" > ${INSTALL_PATH}/armv5-sysroot
    chmod +x ${INSTALL_PATH}/armv5-sysroot
else
    echo "Sysroot linker script exists, skip"
fi
popd

echo "step 7 Build std libs"
pushd ${BUILD_PREFIX}/rust-git
echo "step 7.1 Init submodules"
git checkout ${RUST_VERSION} || (git fetch; git checkout ${RUST_VERSION})
git submodule update --init

echo "step 7.2 Apply patches"
pushd ${BUILD_PREFIX}/rust-git/src/liblibc
git am ${BUILD_PREFIX}/patch/liblibc/*
popd
if [ ${PREINITED} -eq 0 ]; then
    # Patch libunwind
	  patch -p1 < ${BUILD_PREFIX}/patch/libunwind/*
    # Patch libstd
    patch -p1 < ${BUILD_PREFIX}/patch/libstd/0001-disable-compiler-builtins.patch
    patch -p1 < ${BUILD_PREFIX}/patch/libstd/0002-remove-compiler-builtin-extern.patch
fi

echo "step 7.3 Check libbacktrace presence"
if [ -e ${BUILD_PREFIX}/build/libbacktrace.a ]; then
    echo "libbacktrace already here, skip building it"
else
    rm -rf ${BUILD_PREFIX}/build/libbacktrace
    mkdir -p ${BUILD_PREFIX}/build/libbacktrace
    pushd ${BUILD_PREFIX}/build/libbacktrace
    CC="${CC}" AR="${AR}" RANLIB="${AR} s" CFLAGS="${CFLAGS} -fno-stack-protector" ${BUILD_PREFIX}/rust-git/src/libbacktrace/configure  --build=${TARGET} --host=${HOST}
    make -j${THREADS} INCDIR=${BUILD_PREFIX}/rust-git/src/libbacktrace
    
    mv ${BUILD_PREFIX}/build/libbacktrace/.libs/libbacktrace.a ${BUILD_PREFIX}/build
    popd    
fi


echo "step 8 Build libstd"

FEATURES="jemalloc"
if [ "${PANIC_STRATEGY}" = "unwind" ]; then
	  FEATURES="jemalloc backtrace panic_unwind"
fi

function run_with_proper_env {
    FEATURES=${FEATURES} \
            TARGET_JSON="${BUILD_PREFIX}/cfg/${TARGET}.json" \
            TARGET=${TARGET} \
            RUSTC=${RUSTC} \
            CARGO=${CARGO} \
            OPT_LEVEL=${OPT_LEVEL} \
            CARGO_HOME=${CARGO_HOME} \
            PATH=${RUST_PATH}/bin:$PATH \
            LD_LIBRARY_PATH=${RUST_PATH}/lib \
            RUST_TARGET_PATH=${BUILD_PREFIX}/cfg \
            HOST=${HOST} \
            LD=${LD} \
            CC=${CC} \
            AR=${AR} \
            CFLAGS="-Wall -Os -fPIC -D__arm__ -mfloat-abi=soft" $1
}

echo "Features: ${FEATURES}"
echo "step 8.1 Building libstd"
pushd ${BUILD_PREFIX}/rust-git/src/libstd
run_with_proper_env "${CARGO} clean"
run_with_proper_env "${CARGO} build -j${THREADS} --target=${TARGET} --release --features ${FEATURES}"

echo "step 9 Installing"
TARGET_LIB_DIR=${RUST_LIB}/${TARGET}/lib
echo "step 9.1 Installing libs to ${TARGET_LIB_DIR}"
rm -rf ${TARGET_LIB_DIR}
mkdir -p ${TARGET_LIB_DIR}
cp ${BUILD_PREFIX}/rust-git/src/target/${TARGET}/release/deps/* ${TARGET_LIB_DIR}

echo "step 9.2 Installing target config"
cp "${BUILD_PREFIX}/cfg/${TARGET}.json" ${INSTALL_PATH}

echo "step 9.3 Installing convenience cargo wrapper"
cat > ${INSTALL_PATH}/cargo-${TARGET} <<EOF
#!/bin/bash
HERE=${INSTALL_PATH}
APPENDIX=
if [ "\$1" == "build" ]; then
  APPENDIX=--target=${TARGET}
fi
TOOLCHAIN_PATH=${TOOLCHAIN_PATH}
CARGO_HOME=${CARGO_HOME} PATH=\${HERE}/rust/bin:\$PATH LD_LIBRARY_PATH=\${HERE}/rust/lib RUST_TARGET_PATH=\${HERE} HOST=${HOST} TARGET=${TARGET} LD=\${TOOLCHAIN_PATH}/bin/arm-linux-ld CC=\${TOOLCHAIN_PATH}/bin/arm-linux-gcc AR=\${TOOLCHAIN_PATH}/bin/arm-linux-ar ${CARGO} \$* \${APPENDIX}
EOF
chmod +x ${INSTALL_PATH}/cargo-${TARGET}
