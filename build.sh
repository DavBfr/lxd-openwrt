#!/bin/sh

set -e

arch=x86
subarch=64
ver=17.01.4
dist=lede

usage() {
	echo "Usage: $0 [-v|--version <version>] [-p|--packages <packages>] [-f|--files] [--help]"
	exit 1
}

temp=$(getopt -o "v:p:f:" -l "version:,packages:,files:,help" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
	-v|--version)
		ver="$2"; shift 2
		if test ver=snapshot; then
			dist=openwrt
		else
			dist=lede
		fi;;
	-p|--packages)
		packages="$2"; shift 2;;
	-f|--files)
		files="$2"; shift 2;;
	--help)
		usage;;
	--)
		shift; break;;
	esac
done

if [ $# -ne 0 ]; then
        usage
fi

procd_url=https://github.com/openwrt/openwrt/branches/lede-17.01/package/system/procd
procd_extra_ver=lxd-3

lxc_tar=bin/${dist}-${ver}-${arch}-${subarch}-lxd.tar.gz
metadata=bin/metadata.yaml

download_rootfs() {
	if test $ver = snapshot; then
		local rootfs_url=https://downloads.openwrt.org/snapshots/targets/${arch}/${subarch}/${dist}-${arch}-${subarch}-generic-rootfs.tar.gz
	else
		local rootfs_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-${ver}-${arch}-${subarch}-generic-rootfs.tar.gz
	fi

	# global $rootfs
	rootfs=dl/$(basename $rootfs_url)

	download $rootfs_url $rootfs
	check $rootfs $rootfs_url
}

download_sdk() {
	if test $ver = snapshot; then
		local sdk_url=https://downloads.openwrt.org/snapshots/targets/${arch}/${subarch}/${dist}-sdk-${arch}-${subarch}_gcc-7.3.0_musl.Linux-x86_64.tar.xz
	else
		local sdk_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-sdk-${ver}-${arch}-${subarch}_gcc-5.4.0_musl-1.1.16.Linux-x86_64.tar.xz
	fi
	local sdk_tar=dl/$(basename $sdk_url)

	download $sdk_url $sdk_tar
	check $sdk_tar $sdk_url

	# global $sdk
	sdk="build_dir/$(tar tf $sdk_tar|head -1)"

	if ! test -e $sdk; then
		test -e build_dir || mkdir build_dir
		tar xvf $sdk_tar -C build_dir
	fi
}

download() {
	url=$1
	dst=$2
	dir=$(dirname $dst)

	if ! test -e "$dst" ; then
		echo Downloading $url
		test -e $dir || mkdir $dir

		wget -O $dst "$url"
	fi
}

download_sums() {
	local url=$1

	local sums_url="$(dirname $url)/sha256sums"
	local sums_file="dl/sha256sums_$(echo $sums_url|md5sum|cut -d ' ' -f 1)"

	if ! test -e $sums_file; then
		wget -O $sums_file $sums_url
	fi

	return=$sums_file
}

check() {
	local dst=$1
	local dst_url=$2

	download_sums $dst_url
	local sums=$return

	local dst_sum="$(grep $(basename $dst_url) $sums|cut -d ' ' -f 1)"

	sum=$(sha256sum $dst| cut -d ' ' -f1)
	if test -z "$dst_sum" -o $dst_sum != $sum; then
		echo Bad checksum $sum of $dst
		exit 1
	fi
}

download_procd() {
	if ! test -e dl/procd; then
		svn co $procd_url dl/procd
		sed -i -e "s/PKG_RELEASE:=\(\S\+\)/PKG_RELEASE:=\1-${procd_extra_ver}/" dl/procd/Makefile
	fi

	test -e dl/procd/patches || mkdir dl/procd/patches
	cp -a patches/procd/* dl/procd/patches
}

build_procd() {
	if ! test -e $sdk/package/lxd-procd; then
		ln -sfT $(pwd)/dl/procd $sdk/package/lxd-procd
	fi
	local date=$(grep PKG_SOURCE_DATE:= dl/procd/Makefile | cut -d '=' -f 2)
	local version=$(grep PKG_SOURCE_VERSION:= dl/procd/Makefile | cut -d '=' -f 2 | cut -b '1-8')
	local release=$(grep PKG_RELEASE:= dl/procd/Makefile | cut -d '=' -f 2)
	local ipk=$sdk/bin/targets/${arch}/${subarch}/packages/procd_${date}-${version}-${release}_*.ipk

	if ! test -s $ipk; then
	(cd $sdk
	./scripts/feeds update base
	./scripts/feeds install libubox
	./scripts/feeds install ubus
	make defconfig
	make package/lxd-procd/compile
	)
	fi
	test -e bin/packages/${arch}/${subarch} || mkdir -p bin/packages/${arch}/${subarch}
	(cd bin/packages/${arch}/${subarch} && ln -sf ../../../../$ipk .)
}

build_tarball() {
	export SDK="$(pwd)/${sdk}"
	export ARCH=${arch}
	export SUBARCH=${subarch}
	local opts="-m $metadata"
	fakeroot ./build_rootfs.sh $rootfs $opts -o $lxc_tar --packages="${packages}" --files="${files}"
}

build_metadata() {
	local stat=`stat -c %Y $rootfs`
	local date="`date -d \"@${stat}\" +%F`"
	local desc="$(tar xf $rootfs ./etc/openwrt_release -O|grep DISTRIB_DESCRIPTION|sed -e "s/.*='\(.*\)'/\1/")"

	if test ${subarch} = generic; then
		local arch_lxd=${arch}
	else
		local arch_lxd=${arch}_${subarch}
	fi

	cat > $metadata <<EOF
architecture: "$arch_lxd"
creation_date: $(date +%s)
properties:
 architecture: "$arch_lxd"
 description: "$desc"
 os: "OpenWrt"
 release: "$ver"
templates:
EOF

## Add templates
#
# templates:
#   /etc/hostname:
#     when:
#       - start
#     template: hostname.tpl
}

build_image() {
	lxc image import $lxc_tar
}

download_rootfs
download_sdk
download_procd
build_procd
build_metadata
build_tarball
build_image

echo \# start
echo "lxc launch $image <name>"
echo \# set root password
echo "lxc exec <name> passwd root"
