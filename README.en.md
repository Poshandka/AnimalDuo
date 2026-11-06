# AnimalDuo

Current release: **AnimalDuo 1.1**, based on application build **3.0.59** for game **3.0.3**. See the [Chinese release notes](RELEASES/1.1.md) for improved fullscreen presentation, transition coverage, controls and coordinated local-play waiting.

[简体中文](README.md) · English · [English source guide](PUBLIC-SOURCE.md)

**Your game above. Your island at a glance.**

AnimalDuo is an experimental open-source project providing compatibility support and interface enhancements for **Animal Crossing: New Horizons 3.0.3** on **iPad, iPhone and Apple Silicon Mac**.

Its signature feature is an **iPad portrait companion display**, with live map, inventory and Critterpedia pages alongside resident management, island backups and save synchronization tools. These additions make everyday exploring, organizing and island life easier to manage with touch controls and across devices.

The project builds on **nxnative**, using the native-execution approach originating in **d2r-mobile**, and integrates the **Eden Duo** Animal Crossing companion module. Adapted game code runs natively on Apple silicon, with graphics calls translated to Metal.

**This project provides source code only. You must supply game content that you have lawfully obtained and are authorized to use, and build the project yourself. Current validation is primarily on an M4 Mac; platform-specific limits are listed below.**

---

**New in 1.1**

- iPad landscape fills the canvas; portrait game and companion each use half the height.
- Expanded HUD and NookPhone backgrounds, including DIY, Miles and My Designs, retain their intended coverage.
- Black, white and translucent transition masks cover expanded margins.
- Controls default to 3D; an old 2D setting is migrated once. Stick clicks clear the footer, and name confirmation restores landscape controls.
- Companion busy masks cover both sides; connected controllers release space for companion content.
- LAN address selection prefers an available private network over link-local fallback.
- Compatible rooms can pause for a brief background absence: 30 seconds by default or 60 seconds chosen by the host, with a countdown, readiness handshake and explicit end action. Mixed old/new rooms retain ordinary LAN and disable waiting. System eviction or network loss can end a visit early.

The frozen 3.0.59 build passed finite same-Mac game-process and native UI checks. Physical-device background recovery and cross-device Wi-Fi/iCloud behavior remain unverified. This release does not claim improved frame rate or unlimited background execution.

---

**Features for everyday island life**

- **iPad portrait companion**  
  Keep the full game view above and switch between Map, Pockets, Critterpedia, DIY, Today and NookPhone below, with the game and island information visible together.

- **Inventory interaction**  
  Move, swap and sort items, and use the game's native item menus. Operations check item and game state; available actions depend on the current scene.

- **Resident management**  
  Before launching the game, search, filter and replace residents from a catalog of 417 ordinary animal residents. Add a resident to an existing vacant housing plot, or remove one while retaining the plot. The original ten-animal limit remains, and every edit first backs up the complete save.

- **Island backups and restore**  
  Create named checkpoints, browse backup history and restore a complete island. The current save is backed up before restoration. Restoring rolls back both player and island progress.

- **Save synchronization tools**  
  Share complete checkpoints through a common cloud folder selected by the user, with conflict selection and a local offline option. Actual cross-device cloud transfer remains unverified; two independently progressed saves cannot be merged automatically.

- **Experimental local multiplayer**  
  Matching builds and game versions provide island discovery, hosting, visits and return trips. Two independent game processes on one Mac have completed visits, 15/35-second suspension recovery and 60-second expiry handling; physical-device Wi-Fi and background recovery remain unverified.

- **Touch and controller support**  
  Use physical controllers, supported haptics, separate portrait and landscape touch layouts, and manual control visibility or automatic fade. Companion refreshes, shader prewarming, caches and graphics resource management continue to receive improvements.

AnimalDuo's adaptation work focuses on the Apple companion presentation, inventory interaction, resident and save management, touch layouts and runtime fixes. The underlying execution framework and companion modules are credited below.

---

**Platforms and validation scope**

| Target platform | Main experience | Current validation |
|---|---|---|
| **iPad** | Portrait companion, landscape play, touch controls and management interfaces | Physical-device and extended testing of this build remain pending |
| **iPhone** | Landscape play with touch or controller input | Physical-device and extended testing of this build remain pending |
| **Apple Silicon Mac** | Native launcher and shared island saves | Current validation is primarily on an M4 Mac |

The Mac launcher does not currently include the resident-management interface, but it can load an island save edited on another platform. See the build documentation for system, toolchain and device requirements.

The game retains its original target of approximately **30 fps**. Shader prewarming covers recorded scenes; other scenes may still require first-use compilation. Repeatedly entering and leaving houses has produced a loading timeout whose cause remains unresolved.

Official Nintendo online services, direct multiplayer with an original Switch and direct island transfer to or from a Switch are not implemented. For synchronized saves, play on only one device at a time, save normally and wait for the cloud provider to finish uploading before switching devices.

See the [Animal Crossing profile note](dm/games/01006F8002326000/README.md) for detailed test records and known issues.

---

**Get the source and build**

[Download 1.1 source](https://github.com/ShawndYang/AnimalDuo/releases/tag/v1.1) · [English source and build guide](PUBLIC-SOURCE.md) · [Browse the repository](https://github.com/ShawndYang/AnimalDuo)

Use the main branch for the subsequent SDK compatibility, haptics-test and Python-check fixes. The v1.1 tag and downloadable archive retain the original frozen source. Commit-specific check results are available in [GitHub Actions](https://github.com/ShawndYang/AnimalDuo/actions).

**The download contains source code, not an installable game.**

Upgrading from 1.0 (build 3.0.51) to 1.1 (build 3.0.59) keeps game content at 3.0.3. Back up the complete save before updating. Retain the same installation identity and application container rather than uninstalling first; compatible resources can be reused. A thin update cannot bootstrap a first installation. All room members need coordinated-wait support; return readiness is automatic.

Report problems with the [issue form](https://github.com/ShawndYang/AnimalDuo/issues/new?template=bug_report.yml), including build, device/system and reproduction steps. Redact personal paths and device identifiers; do not attach saves, keys or signing material.

Supply the base game, 3.0.3 update, any required DLC and console keys separately, and keep them outside the source directory. The public source archive does not include these inputs, player saves or private signing material.

For build inputs and optional features, start with the [English source guide](PUBLIC-SOURCE.md). The [development guide](docs/development.md) covers the build pipeline and its options; a [Chinese build guide](docs/BUILD.zh-CN.md) is also available.

---

**Technical foundations and open-source licenses**

Thanks to these projects and their contributors:

- **[d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile)**: the native-execution approach and early generic implementation. nxnative started from its generic NSO rewriter, Horizon host, NVN-on-Metal layer and iOS shell.
- **[nxnative](https://github.com/seedds/nxnative)**: the execution host, system-service adaptation, graphics translation and build tools. This snapshot uses upstream revision `b7a5cd43453722d448e07407d88a9c05ed294492` as its base.
- **[Eden Duo](https://github.com/igawa6/eden-duo)** and **[Eden Duo Companions](https://github.com/igawa6/eden-duo-companions)**: the Animal Crossing companion module and interface foundations.
- **[NHSE](https://github.com/kwsch/NHSE)**: save-format references and optional resident and house templates.
- Ryujinx, Zstandard, libvpx, stb and the other dependencies acknowledged below and in the component notices.

<details>
<summary>Further upstream acknowledgements</summary>

- **Ryujinx** (MIT): its `Ryujinx.Graphics.Shader`, `Ryujinx.Common` and `Spv.Generator` 1.3.2 libraries translate Maxwell shaders to SPIR-V. Its kernel and service implementations also provide a behavior reference. Local changes are recorded in [its README](dm/third_party/ryujinx/README.md).
- **[Atmosphère](https://github.com/Atmosphere-NX/Atmosphere)**: mesosphère provides a reference for Horizon synchronization semantics, including address arbitration and condition variables.
- **yuzu**: Maxwell instruction encodings for the shader reference tool and a cross-check for kernel behavior.
- **[LibHac](https://github.com/Thealexbarney/LibHac)**: reads NSPs and layers updates over the base game in `dm/tools/nx_extract`. **hactool** was used for the initial extractions.
- **[SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)**: translates SPIR-V to Metal Shading Language. **[glslang](https://github.com/KhronosGroup/glslang)** compiles GLSL to SPIR-V for the generic OpenGL path.
- **deko3d** (zlib): the texture layout size algorithm ported into `dm/gfx/nvn/nvn_tex.c`.
- **libvpx**, **stb_vorbis**, the **Vulkan headers** and **NVIDIA FLIP**: vendored components with their own licenses, documented in the [third-party component list](dm/third_party/README.md).
- **Capstone**, **lz4**, **fontTools** and **XcodeGen**: tools used by the build.

</details>

Each component is governed by its own license. Relevant d2r-mobile and nxnative code is MIT-licensed; companion modules are GPL-3.0-or-later; other components retain their respective licenses. Combined programs that include the companion are distributed under the requirements of GPL-3.0-or-later.

Use and redistribution must comply with the applicable licenses and retain the required copyright, attribution and modification notices. See [licenses and component notices](LICENSES.txt) and the [companion integration notices](dm/third_party/eden_duo/NOTICES.txt).

---

AnimalDuo is independently maintained and **is not affiliated with, partnered with or endorsed by Nintendo**. Using upstream code does not imply maintenance or support by upstream authors. Game names and trademarks identify the compatibility target; the respective rights belong to their owners.

The project's open-source licenses cover only the relevant code and components. They do not grant rights to game content, trademarks or other third-party material, or authorize circumvention of technical protection measures. Use, building and distribution must comply with applicable law and licenses.
