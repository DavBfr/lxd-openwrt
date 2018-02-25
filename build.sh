#!/bin/sh

set -e

arch=x86
subarch=64
arch_lxd=${arch}_${subarch}
arch_dash=${arch}-${subarch}
ver=17.01.4
image=openwrt
name=openwrt
dist=lede

rootfs_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-${ver}-${arch_dash}-generic-rootfs.tar.gz
rootfs_sum=43886c6b4a555719603286ceb1733ea2386d43b095ab0da9be35816cd2ad8959
rootfs=dl/$(basename $rootfs_url)

sdk_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-sdk-${ver}-${arch}-${subarch}_gcc-5.4.0_musl-1.1.16.Linux-${arch}_${subarch}.tar.xz
sdk_sum=ef8b801f756cf2aa354198df0790ab6858b3d70b97cc3c00613fd6e5d5bb100c
sdk_tar=dl/$(basename $sdk_url)

lxc_tar=${dist}-${ver}-${arch_dash}-lxd.tar.gz
metadata=metadata.yaml

download_rootfs() {
	download $rootfs_url $rootfs
	check $rootfs $rootfs_sum
}

download_sdk() {
	download $sdk_url $sdk_tar
	check $sdk_tar $sdk_sum
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

check() {
	dst=$1
	dst_sum=$2

	sum=$(sha256sum $dst| cut -d ' ' -f1)
	if test $dst_sum != $sum; then
		echo Bad checksum $sum of $dst
		exit 1
	fi
}

build_tarball() {
	fakeroot ./build_rootfs.sh $rootfs $metadata $lxc_tar
}

build_metadata() {
	stat=`stat -c %Y $rootfs`
	date=`date -R -d "@${stat}"`

	cat > $metadata <<EOF
architecture: "$arch_lxd"
creation_date: $(date +%s)
properties:
 architecture: "$arch_lxd"
 description: "OpenWrt $ver $arch_lxd ($date)"
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
	lxc image import $lxc_tar --alias $image
}

download_rootfs
download_sdk
build_metadata
build_tarball
build_image

echo \# start
echo lxc launch --config "raw.lxc=lxc.aa_profile=lxc-container-default-without-dev-mounting" --profile openwrt $image $name
#lxc config
echo \# set root password
echo lxc exec $name passwd root
#echo 'echo "148.251.78.235 downloads.openwrt.org"
