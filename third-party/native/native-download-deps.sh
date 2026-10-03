#!/bin/bash -e

. ./include/depinfo.sh

[ -z "$WGET" ] && WGET=wget

verify_sha() {
	local dir="$1" expected="$2"
	local actual
	actual=$(git -C "$dir" rev-parse HEAD)
	if [ "$actual" != "$expected" ]; then
		echo "ERROR: Commit SHA mismatch in deps/$dir"
		echo "  Expected: $expected"
		echo "  Got:      $actual"
		echo "  Delete deps/$dir and re-run to get a clean copy."
		exit 1
	fi
}

mkdir -p deps && cd deps

# mbedtls
if [ ! -d mbedtls ]; then
	git clone --depth 1 --branch v$v_mbedtls https://github.com/Mbed-TLS/mbedtls.git mbedtls
fi
verify_sha mbedtls $sha_mbedtls

# dav1d
if [ ! -d dav1d ]; then
	git clone --depth 1 --branch $v_dav1d https://code.videolan.org/videolan/dav1d.git dav1d
fi
verify_sha dav1d $sha_dav1d

# libxml2
if [ ! -d libxml2 ]; then
	git clone --depth 1 --branch v$v_libxml2 --recurse-submodules https://github.com/GNOME/libxml2.git libxml2
fi
verify_sha libxml2 $sha_libxml2

# libogg
[ ! -d libogg ] && $WGET https://github.com/xiph/ogg/releases/download/v${v_libogg}/libogg-${v_libogg}.tar.gz && tar -xf libogg-${v_libogg}.tar.gz && mv libogg-${v_libogg} libogg && rm libogg-${v_libogg}.tar.gz

# libvorbis
[ ! -d libvorbis ] && $WGET https://github.com/xiph/vorbis/releases/download/v${v_libvorbis}/libvorbis-${v_libvorbis}.tar.gz && tar -xf libvorbis-${v_libvorbis}.tar.gz && mv libvorbis-${v_libvorbis} libvorbis && rm libvorbis-${v_libvorbis}.tar.gz

# libvpx
if [ ! -d libvpx ]; then
	git clone --depth 1 --branch v$v_libvpx https://gitlab.freedesktop.org/gstreamer/meson-ports/libvpx.git
fi
verify_sha libvpx $sha_libvpx

# libx264
if [ ! -d libx264 ]; then
	git clone https://code.videolan.org/videolan/x264.git libx264
	git -C libx264 checkout $v_libx264
fi
verify_sha libx264 $v_libx264

# ffmpeg
if [ ! -d ffmpeg ]; then
	git clone --depth 1 --branch n$v_ffmpeg https://github.com/FFmpeg/FFmpeg.git ffmpeg
fi
verify_sha ffmpeg $sha_ffmpeg

# freetype2
if [ ! -d freetype ]; then
	git clone --depth 1 --branch VER-$v_freetype https://gitlab.freedesktop.org/freetype/freetype.git freetype
fi
verify_sha freetype $sha_freetype

# fribidi
if [ ! -d fribidi ]; then
	git clone --depth 1 --branch v$v_fribidi https://github.com/fribidi/fribidi.git fribidi
fi
verify_sha fribidi $sha_fribidi

# harfbuzz
if [ ! -d harfbuzz ]; then
	git clone --depth 1 --branch $v_harfbuzz https://github.com/harfbuzz/harfbuzz.git harfbuzz
fi
verify_sha harfbuzz $sha_harfbuzz

# libass
if [ ! -d libass ]; then
	git clone --depth 1 --branch $v_libass https://github.com/libass/libass.git libass
fi
verify_sha libass $sha_libass

# lcms2
if [ ! -d lcms2 ]; then
	git clone --depth 1 -b $v_lcms2 https://github.com/mm2/Little-CMS.git lcms2
fi
verify_sha lcms2 $sha_lcms2

# shaderc
mkdir -p shaderc
cat >shaderc/README <<'HEREDOC'
Shaderc sources are provided by the NDK.
see <ndk>/sources/third_party/shaderc
HEREDOC

if [ ! -d libplacebo ]; then
	git clone https://code.videolan.org/videolan/libplacebo.git libplacebo
	git -C libplacebo checkout $v_libplacebo
	git -C libplacebo submodule update --init --recursive
fi
verify_sha libplacebo $v_libplacebo

# mpv
if [ ! -d mpv ]; then
	git clone https://github.com/mpv-player/mpv.git mpv
	git -C mpv checkout $v_mpv
fi
verify_sha mpv $v_mpv

# fftools_ffi
if [ ! -d fftools_ffi ]; then
	git clone https://github.com/moffatman/fftools-ffi.git fftools_ffi
	git -C fftools_ffi checkout $v_fftools_ffi
fi
verify_sha fftools_ffi $v_fftools_ffi

# media-kit-android-helper
if [ ! -d media-kit-android-helper ]; then
	git clone https://github.com/Predidit/media-kit-android-helper.git
	git -C media-kit-android-helper checkout $v_media_kit_android_helper
fi
verify_sha media-kit-android-helper $v_media_kit_android_helper

cd ..
