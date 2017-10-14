# build-cross-rust

Cross-compile the Rust standard library for armv5

Example build for musl libc:

```
$ git clone https://github.com/snegovick/rust-cross-libs.git
$ cd rust-cross-libs
$ bash ./build-cross-rust.sh  --install-prefix=../ --libc=musl
```

# Test

Build artefacts are stored in ../rust-armv5te-rcross-linux-musleabi.

In order to test cross-cargo we will use hyper and its examples:

```
$ git clone https://github.com/hyperium/hyper.git
$ cd hyper
$ <somewhere>/rust-armv5te-rcross-linux-musleabi/cargo-armv5te-rcross-linux-musleabi build --release
$ <somewhere>/rust-armv5te-rcross-linux-musleabi/cargo-armv5te-rcross-linux-musleabi build --example server --release
$ <somewhere>/rust-armv5te-rcross-linux-musleabi/cargo-armv5te-rcross-linux-musleabi build --example hello --release
$ <somewhere>/rust-armv5te-rcross-linux-musleabi/cargo-armv5te-rcross-linux-musleabi build --example client --release
```

# Issues

  * uclibc is not currently supported by rust. Not sure if it ever will be. Workaround: use musl, carry musl libc with project if needed
  * debug build is  not linking properly because it relies on *__mulodi4*, which is implemented in currently disabled compiler-builtins rust library. Workaround: build with --release

  
# rust-cross-libs

Cross-compile the Rust standard library for custom targets without a full
bootstrap build.

Latest build:

```
$ rustc -V
rustc 1.21.0-nightly (2bb8fca18 2017-08-23)
$ cargo -V
cargo 0.22.0-nightly (7704f7b1f 2017-08-09)
```

Thanks to Kevin Mehall: https://gist.github.com/kevinmehall/16e8b3ea7266b048369d

## Introduction

Although Rust already supports cross-compiling for a great number of targets,
it is tedious to do a full bootstrap build.

Furthermore, the built-in target configurations may not use the best compiler
settings. For example the *armv7_unknown_linux_musleabihf* target defines
"cortex-a8" as cpu and "vfp3" as feature, but there is no target for "cortex-a7"
and "vfp4".

The is a guide to help your cross-compiling the Rust `std` library for your
very own custom target. Example configurations are given for an ARMv5TE and a 
ARMv7-A target using a glibc- or musl-based toolchain.

Note, that for now only dynamic linking is supported. Building a statically
linked executable with a musl-based toolchain is in work.

### Using custom targets

While it is not possible to cross-compile Rust for an unsupported target, unless
you hack it, it offers the possibility to use custom targets with `rustc`:

From the [Rust docs](http://doc.rust-lang.org/1.1.0/rustc_back/target/index.html#using-custom-targets):

>
A target triple, as passed via `rustc --target=TRIPLE`, will first be
compared against the list of built-in targets. This is to ease distributing
rustc (no need for configuration files) and also to hold these built-in
targets as immutable and sacred. If `TRIPLE` is not one of the built-in
targets, rustc will check if a file named `TRIPLE` exists. If it does, it
will be loaded as the target configuration. If the file does not exist,
rustc will search each directory in the environment variable
`RUST_TARGET_PATH` for a file named `TRIPLE.json`. The first one found will
be loaded. If no file is found in any of those directories, a fatal error
will be given. `RUST_TARGET_PATH` includes `/etc/rustc` as its last entry,
to be searched by default.

>
Projects defining their own targets should use
`--target=path/to/my-awesome-platform.json` instead of adding to
`RUST_TARGET_PATH`.

Unfortunately, passing the JSON file path to `rustc` instead of using
`RUST_TARGET_PATH` does not work, so the script internally uses
`RUST_TARGET_PATH` to define the target specification.

## Preparation

### Get a cross-compiler

As we are cross-compiling the Rust libraries we need a cross-compiler, of
course. I am using [Buildroot](https://buildroot.org/), which is a
great tool for generating embedded Linux systems and toolchains for
cross-compilation.

How-to build a toolchain with Buildroot is out of scope. You can simply use the
output path of the Buildroot host build directory or copy the entire folder to
wherever you want the toolchain to be. The example configuration in this
setup assume the toolchain is located in `$HOME/buildroot/output/host`.

For easier use of the toolchain tools, some symlinks are created in
`/usr/local/bin`:

```
sudo ln -s $HOME/buildroot/output/host/arm-buildroot-linux-musleabi/bin/arm-buildroot-linux-musleabi-gcc.br_real /usr/local/bin/arm-unknown-linux-musleabi-gcc
sudo ln -s $HOME/buildroot/output/host/arm-buildroot-linux-musleabi/bin/arm-buildroot-linux-musleabi-ar /usr/local/bin/arm-unknown-linux-musleabi-ar
sudo ln -s $HOME/buildroot/output/host/arm-buildroot-linux-musleabi/bin/arm-buildroot-linux-musleabi-size /usr/local/bin/arm-unknown-linux-musleabi-size
[..]
```

Note, that the setup of the toolchain is totally up to you. The only requirement
is that is supports using a sysroot.

### Define your custom target

Note, that Rust already provides some targets by default, e.g.
*armv5te-unknown-linux-gnueabi*. To allow using a custom ARMv5TE glibc-based
target configuration we need to use a different triple name:
*armv5te-rcross-linux-gnueabi*.

The `cfg` folder contains three example JSON files as starting point for your
very own custom target configuration. Note that the provided configurations
defines almost every possible value you can with the current Rust nightly
version.

I will use the custom target *armv5te-rcross-linux-musleabi* to build a
cross-compiled *"Hello, World!"* with a musl-libc toolchain for an ARMv5TE
soft-float target. However, the necessary configuration steps are given for
all the example targets.

### Cross-compiling with Cargo

Rust uses Cargo to compile the Rust libraries.

For cross-compiling with Cargo we need to make sure to link with the target
libraries and not with the host ones. The `sysroot` directory from the
Buildroot output directory is used for linking with the target libraries. If
this is not done correctly, you will end up with "Relocations in generic ELF"
errors.

#### Sysroot

To allow using a sysroot directory with Cargo lets create an executable shell
script.

Example for *armv5te-rcross-linux-musleabi* target:

```
$ cat /usr/local/bin/arm-unknown-linux-musleabi-sysroot
#!/bin/bash

SYSROOT=$HOME/buildroot/output/host/arm-buildroot-linux-musleabi/sysroot

/usr/local/bin/arm-unknown-linux-musleabi-gcc --sysroot=$SYSROOT $(echo "$@" | sed 's/-L \/usr\/lib //g')

$ chmod +x /usr/local/bin/arm-unknown-linux-musl-sysroot
```

Example for *armv7a-rcross-linux-musleabihf* target:

```
$ cat /usr/local/bin/arm-unknown-linux-musleabihf-sysroot
#!/bin/bash

SYSROOT=$HOME/buildroot/output/host/arm-buildroot-linux-musleabihf/sysroot

/usr/local/bin/arm-unknown-linux-musleabihf-gcc --sysroot=$SYSROOT $(echo "$@" | sed 's/-L \/usr\/lib //g')

$ chmod +x /usr/local/bin/arm-unknown-linux-musleabihf-sysroot

```

Example for *armv5te-rcross-linux-gnueabi* target:

```
$ cat /usr/local/bin/arm-unknown-linux-gnueabi-sysroot
#!/bin/bash

SYSROOT=$HOME/buildroot/output/host/arm-buildroot-linux-gnueabi/sysroot

/usr/local/bin/arm-unknown-linux-gnueabi-gcc --sysroot=$SYSROOT $(echo "$@" | sed 's/-L \/usr\/lib //g')

$ chmod +x /usr/local/bin/arm-unknown-linux-gnueabi-sysroot
```

#### Cargo config

Now we can tell Cargo to use this shell script when linking:

```
$ cat ~/.cargo/config
[target.armv5te-rcross-linux-musleabi]
linker = "/usr/local/bin/arm-unknown-linux-musleabi-sysroot"
ar = "/usr/local/bin/arm-unknown-linux-musleabi-ar"

[target.armv7a-rcross-linux-musleabihf]
linker = "/usr/local/bin/arm-unknown-linux-musleabihf-sysroot"
ar = "/usr/local/bin/arm-unknown-linux-musleabihf-ar"

[target.armv5te-rcross-linux-gnueabi]
linker = "/usr/local/bin/arm-unknown-linux-gnueabi-sysroot"
ar = "/usr/local/bin/arm-unknown-linux-gnueabi-ar"
```

### Get Rust sources and binaries

We fetch the Rust sources from github and get the binaries from the latest
snapshot to run on the host, e.g. for x86_64-unknown-linux-gnu:

    $ git clone https://github.com/joerg-krause/rust-cross-libs.git
    $ cd rust-cross-libs
    $ git clone https://github.com/rust-lang/rust rust-git
    $ wget https://static.rust-lang.org/dist/rust-nightly-x86_64-unknown-linux-gnu.tar.gz
    $ tar xf rust-nightly-x86_64-unknown-linux-gnu.tar.gz
    $ rust-nightly-x86_64-unknown-linux-gnu/install.sh --prefix=$PWD/rust

### Define the Rust environment

As we are running cargo and rustc from the nightly channel we have to set the
correct environment:

    $ export PATH=$PWD/rust/bin:$PATH
    $ export LD_LIBRARY_PATH=$PWD/rust/lib
    $ export RUST_TARGET_PATH=$PWD/cfg

### Define the cross toolchain environment

Define your host, e.g. for a x64 linux host:

    $ export HOST=x86_64-unknown-linux-gnu

Define your target triple, cross-compiler, and CFLAGS.

*armv5te-rcross-linux-musleabi*

    $ export TARGET=armv5te-rcross-linux-musleabi
    $ export CC=/usr/local/bin/arm-unknown-linux-musleabi-gcc
    $ export AR=/usr/local/bin/arm-unknown-linux-musleabi-ar
    $ export CFLAGS="-Wall -Os -fPIC -D__arm__ -mfloat-abi=soft"

*armv7a-rcross-linux-musleabihf*

    $ export TARGET=armv7a-rcross-linux-musleabihf
    $ export CC=/usr/local/bin/arm-unknown-linux-musleabihf-gcc
    $ export AR=/usr/local/bin/arm-unknown-linux-musleabihf-ar
    $ export CFLAGS="-Wall -Os -fPIC -D__arm__ -mfloat-abi=hard"

Note, that you need to adjust these flags depending on your custom target.

## Run the script

Make sure you've followed the preparation.

Two panic strategies are supported: abort and unwind. Although the panic strategy
is already defined in the json target configuration, it is still necessary to take
care of this setting.

### Panic strategy: Abort

If your target uses the *abort* panic strategy, no additional parameter is required:

    $ ./rust-cross-libs.sh --rust-prefix=$PWD/rust --rust-git=$PWD/rust-git --target=$PWD/cfg/$TARGET.json
    [..]
    Libraries are in /home/joerg/rust-cross-libs/rust/lib/rustlib/armv5te-rcross-linux-musleabi/lib

### Panic strategy: Unwind

For now, the build script needs to know when to build the std library with the
*panic_unwind* strategy and the backtrace feature. Therefor, setting 
`--panic=unwind` is required:

    $ ./rust-cross-libs.sh --rust-prefix=$PWD/rust --rust-git=$PWD/rust-git --target=$PWD/cfg/$TARGET.json --panic=unwind
    [..]
    Libraries are in /home/joerg/rust-cross-libs/rust/lib/rustlib/armv5te-rcross-linux-musleabi/lib

## Hello, world!

Make sure you've followed the preparation and defined your Rust environment
(PATH, LD_LIBRARY_PATH, RUST_TARGET_PATH).

Cargo the hello example app:

    $ cargo new --bin hello
    $ cd hello
    $ cargo build --target=$TARGET --release

Check:

    $ file target/$TARGET/release/hello
    target/armv5te-rcross-linux-musleabi/release/hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-arm.so.1, not stripped

    $ arm-linux-size target/$TARGET/release/hello
       text	   data	    bss	    dec	    hex	filename
      59962	   1924	    132	  62018	   f242	target/armv5te-rcross-linux-musleabi/release/hello
