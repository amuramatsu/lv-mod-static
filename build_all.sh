#! /bin/sh

./build.sh arm64
./build.sh armhf
./build.sh armel
./build.sh i486
./build.sh amd64
./build.sh mips
./build.sh mipsel
./build.sh powerpc
./build.sh ppc64el
./build.sh riscv32
./build.sh riscv64
./build.sh s390x

dist=$(echo lv_mod-static-*_musl-*)
tar zcf "${dist}.tar.gz" "./${dist}"
