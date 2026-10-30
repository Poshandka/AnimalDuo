# AnimalDuo 中文构建与使用说明

[返回中文首页](../README.md) · [English source guide](../PUBLIC-SOURCE.md)

## 这是什么

AnimalDuo 公开的是《集合啦！动物森友会》3.0.3 的 Apple 移植增强源码。游戏代码通过宿主原生执行，图形接口由 Metal 实现，iPad 竖屏副屏使用 Eden Duo 的动森模块。

本仓库不提供游戏包、主机密钥、固件、玩家存档、生成的岛民模板或已签名安装包。构建时使用自己的匹配资源，所有提取文件和输出都应放在源码目录之外。

## 平台与验证

| 平台 | 当前方案 |
| --- | --- |
| iPad | 通用 arm64 iOS 构建；竖屏为游戏加副屏，横屏为完整游戏画面及可选触控按键。 |
| iPhone | 与 iPad 共用源码／通用安装包，使用横屏布局。 |
| Apple Silicon Mac | 原生 arm64 宿主；历史发布包使用 Apple-m1 CPU 基线，最低 macOS 27。Mac 原生启动器不提供 Swift 岛民管理界面。 |

历史构建使用 Xcode 27.1，iOS 最低目标为 26。构建目标不是所有设备都已经实测的保证；M4 Mac 的测试结果也不等同于 iPad、iPhone 或 M2 的实测结果。

## 准备环境与基础构建

在 Apple Silicon Mac 上准备 Xcode 及其命令行工具，并按[开发文档](development.md)安装构建依赖。NSP 提取、重写和着色器转换还会使用该文档列出的 .NET、Python、XcodeGen 及其他工具。

克隆仓库：

    git clone --depth 1 https://github.com/ShawndYang/AnimalDuo.git
    cd AnimalDuo

查看打包脚本的完整参数：

    python3 scripts/build_ipa_from_nsp.py --help

下面是基础处理流程的示例；将示例路径换成自己的外部游戏目录与密钥文件：

    python3 scripts/build_ipa_from_nsp.py /external/game-packages -k /external/keys/prod.keys --platform mac --keep-extracted --language zh-Hans

该流程用于提取、重写、转换着色器及准备 Mac 运行所需内容。普通 iOS 打包可选择 --platform ios，可双击的 Mac 应用选择 --platform mac-app。基础命令不会替你提供岛民目录、模板或已生成的对话补丁；需要这些增强功能时，继续完成下面的准备和最终打包步骤。

对外发布给其他 Apple Silicon 机器时，应使用兼容的 CPU 基线。历史通用 Mac 宿主的构建命令为：

    make -C dm/host GAME=01006F8002326000 'CFLAGS=-O1 -g -Wall -Wno-unused-function -arch arm64 -mcpu=apple-m1 -mmacosx-version-min=27.0' dmhost

## 岛民目录与初期对话补丁

岛民管理保留原版 10 位动物上限。增加动物需要已有的空住宅地块，不能把“增加岛民”理解为任意新增建筑位置。修改前应先建立完整存档备份；读盘、游戏版本、存档哈希和并发写入等检查失败时，工具会拒绝修改。

可选岛民目录由[生成脚本](../scripts/build_acnh_resident_catalog.py)从自己的 RomFS 读取；模板来自单独准备的 [NHSE cb07454 源码](https://github.com/kwsch/NHSE/tree/cb07454)。查看参数：

    python3 scripts/build_acnh_resident_catalog.py --help

生成示例：

    python3 scripts/build_acnh_resident_catalog.py /external/game/RomFS /external/game/resident_catalog.json --templates /external/NHSE/NHSE.Villagers/Resources

模板目录应指向本地 NHSE 源码中的 NHSE.Villagers/Resources。生成结果包含游戏数据，保留在外部构建目录，不要提交到源码仓库；模板相关许可和对应源码应按原组件要求保留。

替换最初两位岛民的性格后，原游戏的部分初期剧情分支可能缺少台词或动作。打包含岛民管理的版本前，从自己的完整 3.0.3 RomFS 生成补丁并验证：

    python3 scripts/build_acnh_starter_dialogue.py /external/game/RomFS /external/game/dialogue-overlay --report /external/game/dialogue-overlay.json --merged-romfs /external/game/dialogue-RomFS
    python3 scripts/build_acnh_starter_dialogue.py /external/game/dialogue-RomFS --verify

补丁只补缺失或空白的初期内容，保留已有非空台词及岛民的初始身份、住宅与建设状态。生成后的对话资源仍属于外部游戏构建数据。

## 最终打包

iOS 使用 [build_ipa.sh](../dm/ios/tools/build_ipa.sh)。对应功能构建需要设置以下外部输入：

| 变量 | 含义 |
| --- | --- |
| GAME | 动森基础 Title ID：01006F8002326000。 |
| W | 外部 iOS 构建工作目录。 |
| PATCHED | 对应 3.0.3 的重写后模块目录。 |
| ROMFS | 已验证的合并对话资源目录，例如 /external/game/dialogue-RomFS。 |
| MSL_IOS | 同一转换链生成的 iOS Metal 库目录。 |
| AOC | 匹配的附加内容目录。 |
| FONT_PY | 安装了字体构建依赖的 Python。 |
| DM_CONTROL_NACP | 原始游戏 control.nacp，保留游戏语言能力等元数据。 |
| DM_RESIDENT_CATALOG | 在外部生成的岛民目录 JSON。 |
| DM_RESIDENT_LICENSE | 随模板提供的许可声明文件。 |

历史通用配置还使用 DM_LANG=zh-Hans 和 DM_PSO_GPUS=none。具体命令、输出目录和先后顺序见 [BUILD-RESIDENT-DIALOGUE-FIX.txt](../BUILD-RESIDENT-DIALOGUE-FIX.txt)及[底层开发文档](development.md)。生成的 Gen 目录是构建输出，不应提交。

Mac 使用 [pack_app.py](../dm/mac/pack_app.py)，传入匹配的宿主、重写模块、合并 RomFS、Mac 着色器库、配置表、字体和 DLC。需要启动时的云存档入口时使用 --cloud-save-setup。Mac 的本地临时签名与 iOS 的未签名打包是两套流程。

公开仓库不包含 Apple 签名身份或设备配置。iOS 构建产物为未签名 IPA，需要使用自己的侧载方式；更新已有安装时保持安装身份，先备份存档。

## 游戏中的功能

**副屏与按键。** iPad 竖屏上方为完整游戏画面，下方为六页副屏，底栏置底、触控按键分布在左右两侧。操作副屏时会暂时隐藏按键。横屏隐藏副屏；没有实体手柄时使用淡色触控按键，持续操作约 8 秒后隐藏图案但仍能按原位置操作，停止约 1.5 秒后恢复。手动隐藏会关闭虚拟按键触控，与自动淡出不同。按键布局可以单独调整横竖屏配置。

**背包。** 点选物品后可调用游戏允许的原生操作；支持拖动、点选移动、交换和整理。读盘、对话、联机或物品状态变化时，操作可能暂时不可用。修改通过正常游戏保存落盘。

**云存档。** 在各设备选择同一个 iCloud Drive 文件夹。游戏运行时仍使用本机存档，成功保存后发布完整检查点；等待 iCloud 上传完成后再切换设备。两台设备分别玩出的新进度需要选择完整版本，不能自动合并。无法访问云目录时可使用本机存档继续，冲突留待下次处理。命名备份保存在当前设备，恢复前会先备份被替换的进度。

**局域网。** 需要匹配的移植版、游戏版本及本地网络权限。机场可用后，通过本地联机菜单开岛或出行。现有完整登岛与返程验证来自同一台 Mac 的两个独立游戏进程；实际跨设备 Wi-Fi 验证仍有待补充。原版 Switch 及任天堂在线服务不属于当前联机范围。

**性能记录。** 默认关闭，开启后最多记录 30 分钟真实显示帧间隔、内存和温控等状态。它是诊断工具，不会改变游戏原有 30 帧目标。

## 已知问题与反馈

目前仍有 Xbox USB 手柄无震动、部分室内／物品路径贴图维度警告，以及反复切换房屋时一次未定位的加载就绪超时。未预热的状态仍可能首次编译，现有优化不等于全部场景都不会卡顿。

GitHub 的 Python 静态检查相对上游基线有 5 条待修复项。脱敏和源码完整性校验通过，与全部构建检查通过是不同的结论。

完整历史测试、已修问题及待验证范围见[动森适配记录](../dm/games/01006F8002326000/README.md)。反馈问题时可提供版本、平台和操作步骤；日志应先去除个人路径等信息，不要公开密钥、签名资料或完整玩家存档。

## 许可与原作者

原 nxnative 的 MIT 声明保留；Eden Duo 副屏模块和作者编写的本地化文本采用 GPL-3.0-or-later，BC 解码等组件另有 MPL-2.0／MIT 等许可，不能将整个组合构建简单视为全部 MIT。

参见 [LICENSES.txt](../LICENSES.txt)、[Eden Duo 组件声明](../dm/third_party/eden_duo/NOTICES.txt)及[英文源码说明](../PUBLIC-SOURCE.md)。本项目与 Nintendo 或上述上游项目均无官方隶属或背书关系。
