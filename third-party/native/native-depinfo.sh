#!/bin/bash -e

## Dependency versions

v_sdk=9123335_latest
v_ndk=27.2.12479018
v_sdk_build_tools=34.0.0

v_libass=0.17.1
v_harfbuzz=7.2.0
v_fribidi=1.0.12
v_freetype=2-13-0
v_mbedtls=3.4.0
v_dav1d=1.2.0
v_libxml2=2.10.3
v_ffmpeg=7.1.3
v_mpv=32a164cc017acab50389f2194f720ccfd0b01a28
v_libplacebo=d4624cbfb37fdef337a7da5794b66202671a89cd
v_lcms2=lcms2.17
v_libogg=1.3.5
v_libvorbis=1.3.7
v_libvpx=1.13.0
v_libx264=023112c6f2f575c72e9f26274d183b70996fb542
v_fftools_ffi=10070acb2c090edda86dba431f6c281145ceb221
v_media_kit_android_helper=b768ce102cfa9b5ddec618bb939d689d1b0899fa
v_gas_preprocessor=ac1836309c2e77023c228b7184485597286289d3

## Pinned commit SHAs for tag-based clones
sha_mbedtls=1873d3bfc2da771672bd8e7e8f41f57e0af77f33
sha_dav1d=676a864a11af2c0522e1f992e770589543894686
sha_libxml2=f507d167f1755b7eaea09fb1a44d29aab828b6d1
sha_libvpx=d6eb9696aa72473c1a11d34d928d35a3acc0c9a9
sha_ffmpeg=f46e514491172d15bd74b4abb1814cd2f05a763e
sha_freetype=de8b92dd7ec634e9e2b25ef534c54a3537555c11
sha_fribidi=6428d8469e536bcbb6e12c7b79ba6659371c435a
sha_harfbuzz=a321c4fee56b15247c10f9aa3db7e7ccb3b8173b
sha_libass=e8ad72accd3a84268275a9385beb701c9284e5b3
sha_lcms2=5176347635785e53ee5cee92328f76fda766ecc6


## Dependency tree
# I would've used a dict but putting arrays in a dict is not a thing

dep_mbedtls=()
dep_dav1d=()
dep_libvorbis=(libogg)
if [ -n "$ENCODERS_GPL" ]; then
	dep_ffmpeg=(mbedtls dav1d libxml2 libvorbis libvpx libx264)
else
	dep_ffmpeg=(mbedtls dav1d libxml2)
fi
dep_freetype2=()
dep_fribidi=()
dep_harfbuzz=()
dep_libass=(freetype fribidi harfbuzz)
dep_lua=()
dep_shaderc=()
dep_libplacebo=(shaderc lcms2)
if [ -n "$ENCODERS_GPL" ]; then
	dep_mpv=(ffmpeg libass libplacebo fftools_ffi)
else
	dep_mpv=(ffmpeg libass libplacebo)
fi
