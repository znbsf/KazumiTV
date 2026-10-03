# 来源、依赖与资源

KazumiTV保留Kazumi迁移工作的GPL-3.0许可与来源署名。上游项目：https://github.com/Predidit/Kazumi 。本分支不代表上游官方TV版本。

当前原生APK主要运行时组件：

| 组件 | 许可 | 来源 |
| --- | --- | --- |
| Kotlin / kotlinx.coroutines | Apache-2.0 | https://github.com/JetBrains/kotlin / https://github.com/Kotlin/kotlinx.coroutines |
| AndroidX Activity / Lifecycle / Compose / TV / Media3 | Apache-2.0 | https://android.googlesource.com/platform/frameworks/support/ |
| Coil | Apache-2.0 | https://github.com/coil-kt/coil |
| OkHttp / Okio | Apache-2.0 | https://github.com/square/okhttp / https://github.com/square/okio |
| jsoup | MIT | https://github.com/jhy/jsoup |
| Public Suffix List（OkHttp 内含的域名后缀数据） | MPL-2.0 | https://publicsuffix.org/list/public_suffix_list.dat |

完整Apache-2.0与jsoup MIT文本位于LICENSES目录，项目GPL全文位于根目录LICENSE。准确版本见app/build.gradle.kts及Gradle依赖图。此表为主要依赖索引，不能替代各依赖自带的完整许可/NOTICE；发行前持续核对传递依赖。Junit与测试JSON仅用于本地/仪器测试，不作为应用功能发布。

应用标志及电视横幅为本项目独立矢量设计；使用设备系统字体。海报为运行时在线内容，不打包到应用；README截图用于说明应用界面，不声明拥有节目海报版权。自制多轨道测试视频及派生HLS/DASH的生成说明见app/src/androidTest/assets/offline-fixtures.md。

旧Flutter版依赖和资源以对应发布标签下的原工程、许可文件与Flutter许可登记为准，不与原生APK依赖混为一谈。

## Public Suffix List 数据

OkHttp 的库代码许可与其附带数据许可应分别保留。当前 APK 内的 `okhttp3/internal/publicsuffix/NOTICE` 明确将 `publicsuffixes.gz` 指向 Public Suffix List，采用 MPL-2.0；原样声明另存于 [LICENSES/OkHttp-publicsuffix-NOTICE.txt](LICENSES/OkHttp-publicsuffix-NOTICE.txt)。数据源码见 [Public Suffix List](https://publicsuffix.org/list/public_suffix_list.dat)，许可全文见 [Mozilla MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)。不将整份 OkHttp 错标为 MPL。

## 对应源码与上游声明

原生发行包的对应源码应使用同一 Release 标签下的本仓库源码及构建文件，不能只链接上游 Flutter 工程。旧路线使用其对应标签。去除过时宣传、手机截图和旧渠道说明不意味着删除仍适用的 GPL 许可、上游来源、原有版权/许可声明或迁移代码归属；这些内容继续保留。根目录 GPL 全文和本文件必须随发行材料提供。后续新引入或移植模块应记录具体来源版本和其自身许可，不将当前依赖表视为全量许可核验完成。
