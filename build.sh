#! /bin/sh
#
# build script with dockcross
#

lv_mod_version="4.51.d+001"
lv_mod_sha1="05cc5b98873c3f65cc8f8322e53ed4a18091b84a"
netbsd_curses_version="0.3.2"
netbsd_curses_sha1="ffffe30ed60ef619e727260ec4994f7bf819728e"
musl_version="1.2.5"
musl_sha1="36210d3423172a40ddcf83c762207c5f760b60a6"
musl_patch1="https://www.openwall.com/lists/musl/2025/02/13/1/1"
musl_patch1_sha1="83b881fbe8a5d4d340977723adda4f8ac66592f0"
musl_patch2="https://www.openwall.com/lists/musl/2025/02/13/1/2"
musl_patch2_sha1="0ceaa0467429057efce879b6346efa4f58c7cd4d"

release_dir="lv_mod-static-${lv_mod_version}_musl-${musl_version}-${netbsd_curses_version}"

if [ -z "$1" ]; then
    echo "Usage: $0 ARCH"
    echo ""
    echo "   supported ARCHes are"
    echo "     arm64, armhf, armel, i486, amd64, mips, mipsel,"
    echo "     powerpc, ppc64el, s390x"
    echo ""
    exit 1
fi

CFLAGS=
LDFLAGS=
musl_configure=
lv_mod_configure=
lv_mod_patch="$(pwd)/lv-mod-${lv_mod_version}.patch"
curses_configure=
curses_patch="$(pwd)/netbsd-curses-${netbsd_curses_version}.patch"
strip=
arch="$1"
link_hack=
case $arch in
    arm64)
	dockcross_arch=linux-arm64
	;;
    armhf)
	dockcross_arch=linux-armv7
	CFLAGS="-mfloat-abi=hard"
	;;
    armel)
	dockcross_arch=linux-armv5
    	CFLAGS="-mfloat-abi=soft"
    	;;
    i486)
	#dockcross_arch=linux-x86
	dockcross_arch=linux-i686
	musl_configure="--target i386-linux-gnu RANLIB=ranlib"
	lv_mod_configure="--target i386-unknown-linux-gnu"
	CFLAGS="-march=i486 -m32"
	LDFLAGS="-m32"
	link_hack=-melf_i386
	strip=strip
	;;
    amd64)
	dockcross_arch=linux-x64
	;;
    mips) 
	dockcross_arch=linux-mips
	;;
    mipsel)
	dockcross_arch=linux-mipsel
	;;
    powerpc)
	dockcross_arch=linux-ppc
	CFLAGS="-mbig -mlong-double-64"
	;;
    ppc64el)
	dockcross_arch=linux-ppc64le
	CFLAGS="-mlong-double-64"
	;;
    riscv32)
	dockcross_arch=linux-riscv32
	;;
    riscv64)
	dockcross_arch=linux-riscv64
	;;
    s390x)
	dockcross_arch=linux-s390x
	;;
    *)
	echo "unknown archtecture $arch"
	exit 1
	;;
esac

build_dir="$(pwd)/build"
archives_dir="$(pwd)/archives"

sha1_digest() {
    FILE="$1"
    shasum=
    for bindir in /usr/bin /usr/local/bin /usr/pkg/bin /opt/local/bin; do
	if [ -x "${bindir}/shasum" ]; then
	    shasum="${bindir}/shasum"
	    break
	fi
    done
    if [ x"$shasum" = x"" ]; then
	shasum='openssl dgst -sha1 -r'
    fi
    $shasum "$FILE" | awk '{print $1}'
}

download() {
    URL="$1"
    SHA="$2"
    filename="$3"
    [ -d "$archives_dir" ] || mkdir -p "$archives_dir"
    if [ x"$filename" = x"" ]; then
	filename="$(basename "$URL")"
    fi
    if [ -r "${archives_dir}/${filename}" ]; then
	digest=$(sha1_digest "${archives_dir}/${filename}")
	if [ x"$digest" = x"$SHA" ]; then
	    return
	fi
	rm -f "${archives_dir}/${filename}"
    fi
    curl -L -o "${archives_dir}/${filename}" "${URL}"
}

if [ -d "$build_dir" ]; then
  echo "= removing previous build directory"
  rm -rf "$build_dir"
fi

mkdir -p "$build_dir"
curdir="$(pwd)"
cd "$build_dir"
working_dir="$(pwd)"

docker run --rm "dockcross/${dockcross_arch}" > ./dockcross
chmod +x dockcross
./dockcross update # update dockcross environment!
dockerwork_dir=$(./dockcross bash -c 'echo -n $(pwd)')

# download tarballs
echo "= downloading lv-mod"
download "https://github.com/amuramatsu/lv-mod2/archive/refs/tags/lv-${lv_mod_version}.tar.gz" $lv_mod_sha1 "lv-mod-${lv_mod_version}.tar.gz"

echo "= extracting lv-mod"
gzip -cd "${archives_dir}/lv-mod-${lv_mod_version}.tar.gz" | tar xf - 

echo "= downloading musl"
download "http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz" $musl_sha1
download $musl_patch1 $musl_patch1_sha1 musl.patch1
download $musl_patch2 $musl_patch2_sha1 musl.patch2

echo "= extracting musl"
musl_dir="musl-${musl_version}"
gzip -cd "${archives_dir}/musl-${musl_version}.tar.gz" | tar xf -
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch1")
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch2")

echo "= downloading netbsd-curses"
download "http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-${netbsd_curses_version}.tar.xz" $netbsd_curses_sha1

echo "= extracting netbsd-curses"
xz -cd "${archives_dir}/netbsd-curses-${netbsd_curses_version}.tar.xz" | tar xf -

echo "= building musl"

install_dir="${dockerwork_dir}/musl-install"
musl_dir="musl-${musl_version}"

./dockcross bash -c "cd ${musl_dir} && ./configure '--prefix=${install_dir}' --disable-shared ${musl_configure} 'CFLAGS=$CFLAGS'"
./dockcross bash -c "cd ${musl_dir} && make install"

echo "= setting CC to musl-gcc"
CC="${dockerwork_dir}/musl-install/bin/musl-gcc"
if [ ! -z "$link_hack" ]; then
    echo "= hack for link with musl-gcc"
    sed -i.bak "s/-dynamic-linker/$link_hack -dynamic-linker/" "${working_dir}/musl-install/lib/musl-gcc.specs"
fi

echo "= building netbsd-curses"

curses_dir="netbsd-curses-${netbsd_curses_version}"
(cd "$curses_dir" && patch -p1 < "$curses_patch")
./dockcross bash -c "cd '${curses_dir}' && make 'CC=$CC' 'HOSTCC=gcc' 'CFLAGS=-Os -std=gnu11 $CFLAGS' 'LDFLAGS=-static $LDFLAGS' 'PREFIX=${install_dir}' all-static install-static"

echo "= building lv-mod"

lv_mod_dir="lv-mod2-lv-${lv_mod_version//+/-}"
(cd "$lv_mod_dir" && patch -p1 < "$lv_mod_patch")
./dockcross bash -c "cd '${lv_mod_dir}/build' && ../configure 'CC=$CC -static $CFLAGS' 'LDFLAGS=$LDFLAGS' 'LIBS=-lcurses -lterminfo' ${lv_mod_configure} --host=x86_64-unknown-linux-gnu"
./dockcross bash -c "cd '${lv_mod_dir}/build' && make"

cd "${curdir}"

[ -d "${release_dir}" ] || mkdir -p "${release_dir}"

echo "= copy lv binary"
cp "${build_dir}/${lv_mod_dir}/lv.1"     "${release_dir}"
cp "${build_dir}/${lv_mod_dir}/lv.hlp"   "${release_dir}"
cp "${build_dir}/${lv_mod_dir}/GPL.txt"  "${release_dir}"
cp "${build_dir}/${lv_mod_dir}/build/src/lv" "${release_dir}/lv-${arch}"
if [ x"$strip" = x"" ]; then
    "${build_dir}/dockcross" bash -c 'STRIP=$(echo $CC|sed s/-gcc\$/-strip/); $STRIP -s '"'${release_dir}/lv-${arch}'"
else
    "${build_dir}/dockcross" bash -c "$strip -s '${release_dir}/lv-${arch}'"
fi

# remove ACL at macOS
uname_s=$(uname -s)
if [ x"$uname_s" = x"Darwin" ]; then
    for a in com.docker.owner com.docker.grpcfuse.ownership; do
        xattr -d "$a" "${release_dir}/lv-${arch}" >/dev/null 2>&1
    done
fi

echo "= done"
