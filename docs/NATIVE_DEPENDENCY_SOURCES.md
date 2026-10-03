# 播放器依赖与对应源码

本版沿用固定 media-kit `994465d9bfca3f39d0b41199d16e7fd93fe97881`，未改动 libmpv 二进制。APK 内的 Dart/Flutter 依赖声明以及 MiSans、native 依赖原文可从设置中的许可证页查看；字体保持原始字节。

## 固定构建来源

- [libmpv Android v1.2.7](https://github.com/Predidit/libmpv-android-video-build/releases/tag/v1.2.7)，构建提交 `dd2bfba8209bcd22e2d4c79f125b40e619e637ed`。
- [随源码保存的构建配方和全部 patches](../third-party/native/libmpv-build-dd2bfba-source.zip)。它是构建仓库归档，依赖本体按下面固定索引获取。
- [原始下载脚本](../third-party/native/native-download-deps.sh)和[固定版本、SHA](../third-party/native/native-depinfo.sh)给出对应上游仓库。解包构建归档后按其 README/default flavor 构建，保留 patches；不以浮动 main 代替固定依赖。
- FFmpeg `n7.1.3` / `f46e514491172d15bd74b4abb1814cd2f05a763e`，mpv `32a164cc017acab50389f2194f720ccfd0b01a28`。配方为 FFmpeg `--disable-gpl --disable-nonfree --enable-version3`、mpv `-Dgpl=false`。
- Native 构建使用 NDK `27.2.12479018`；shaderc 来自该 NDK 的 `sources/third_party/shaderc`，其构建方式在固定归档 `buildscripts/scripts/shaderc.sh`，不是另取最新版。应用 Android 构建使用的 NDK 28.2 不改变这些既有 native 库。

完整的原始来源 URL、下载资料 SHA256、三 ABI JAR/libmpv 哈希与依赖版本见 [SOURCE-INDEX.json](../third-party/native/SOURCE-INDEX.json)，许可原文见 [LICENSES](../third-party/native/LICENSES)。构建仓库的 MIT 声明不替代各库自身的许可。

应用对应源码由本 Release 的精确集成提交提供；保留 pubspec.lock、Android 配置和构建说明。Release 附带 TV 对应源码和上述 native 构建资料，源码获取不要求应用签名私钥。
