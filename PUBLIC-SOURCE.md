# AnimalDuo public source

[简体中文构建说明](docs/BUILD.zh-CN.md) · [中文首页](README.md) · English

## Scope

This is the AnimalDuo 1.3 source snapshot for application build 3.0.76 and Animal Crossing 3.0.3. It is based on nxnative revision b7a5cd43453722d448e07407d88a9c05ed294492 and preserves the original source and copyright notices. The tree contains the Animal Crossing profile and small tool-test fixtures. [Release notes](RELEASES/1.3.md)

Included extensions:

- Shared iPad/iPhone build support and a native Apple Silicon Mac package.
- Opt-in LAN play between matching native ports. Official Nintendo online services and physical Switch interoperability are not implemented.
- Resident replacement, vacant-plot addition and deletion, a generated searchable catalog, whole-save guards and backups, with a ten-animal limit.
- Full-island checkpoints through a user-selected cloud folder, conflict selection, local fallback, named local backups and restore.
- The Eden Duo six-page companion on iPad in portrait, native item-menu actions, checked item moves/exchanges, sorting and themes. Landscape retains the full game view.
- Integrated portrait touch controls, landscape automatic fade, manual visibility, editable layouts and native touchscreen events.
- Shared Apple controller-haptics fixes; Xbox USB vibration remains unresolved.
- Direct startup, optional presented-frame recording, bounded companion caches, immutable layout templates, expanded measured pipeline preparation, incremental memory-pool indexes and secondary-view retirement.
- A build-time starter-dialogue overlay generated from the builder's own game resources. It retains resident origin/housing state and preserves nonempty original dialogue.

The Mac native launcher does not provide the Swift resident-management UI; it can load the same edited island and generated dialogue overlay. This list does not promise feature parity across every Apple device.

## AnimalDuo 1.2 / application build 3.0.68

The release includes the hosted CI fixes that followed v1.1 and the local-play, resident
management and touch input updates below. A compatible existing installation can reuse
the installed resources for game 3.0.3. A first installation needs matching game resources.
The fullscreen, transition and coordinated waiting changes were introduced in 1.1.
[1.1 release notes](RELEASES/1.1.md)

### Local-play recovery / application builds 3.0.60 and 3.0.61

Pending guest socket requests count only active time during a coordinated pause. The companion identifies the local player during visits by using the game's network-player/home-resident mapping and verifies the exact Land-only visitor save class before reading it. An admitted session retains its peer transport and recreates defunct Bonjour discovery objects after returning from the background. [Guest socket and companion notes](BUILD-LAN-RECOVERY.txt) · [Short-return notes](BUILD-LAN-SHORT-RETURN.txt)

### Resident speech / application builds 3.0.62 and 3.0.63

Resident replacement resets the localized phrase array, player nicknames, custom greetings and associated markers. The catalog supplies the default phrase for each of the eleven save languages. Separate menu actions restore the default phrase or the default nicknames and greetings for residents already on the island. [Catchphrase notes](BUILD-RESIDENT-PHRASE.txt) · [Speech audit](BUILD-RESIDENT-AUDIT.txt)

### Resident lifecycle and backup recovery / application builds 3.0.64 to 3.0.66

New animals use the island's last saved calendar date. Editing checks pending NPC references in every house and verifies the complete save inventory before an edit or restore. Backup metadata loads on the manager's worker. Recovery can browse and restore a verified backup even when the current save cannot be read, preserving unreadable files separately. [Lifecycle notes](BUILD-RESIDENT-LIFECYCLE.txt) · [Housing notes](BUILD-RESIDENT-SAFETY.txt) · [Recovery notes](BUILD-RESIDENT-RECOVERY.txt)

### Left stick slow-walk zone / application build 3.0.68

The launcher's touch layout editor adjusts how far the left stick can travel before it leaves the slow-walk range. Each orientation stores a separate radius as a percentage of the outer ring. Existing profiles keep their linear response until the slider is moved. See [Editable touch control geometry](docs/reference/services.md#editable-touch-control-geometry).

## AnimalDuo 1.3 / application build 3.0.76

### Portrait companion and stick scaling / application build 3.0.69

An attached controller lets the companion paint its backdrop across the full surface in one pass. The portrait size slider scales both sticks while their touch regions stay inside the side rails. The slow-walk radius follows the visible left ring. [Controller companion layout](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Portrait button scaling / application build 3.0.70

The portrait size slider adjusts the face buttons, D-pad, shoulders, menu pills and stick clicks. Each group grows within the available space in its side rail. The face outlines retain clearance and adjacent buttons still accept diagonal presses. The menu pills keep their 44-point minimum touch targets. [Touch layout details](docs/reference/services.md#editable-touch-control-geometry)

### Portrait face spacing and dock clearance / application build 3.0.71

The face diamond uses the vertical room above the plus button. The companion body and both touch rails end above the dock with a shared gap, and the wallpaper continues through the separation. The dock uses its authored navigation widgets. [Controller companion layout](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Borderless portrait companion / application build 3.0.72

A single wallpaper fills the companion surface. The original Map, Critters and DIY textures use their panel interiors, and alternate themes omit the decorative frame and shadow. The wider Y and A positions share their fitted touch geometry and stay inside the right rail. [Controller companion layout](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Bottom-edge companion dock / application build 3.0.73

The navigation plate fills the physical bottom edge. The window clips its bottom corners, and the tabs occupy a separate row that fits the safe area. The companion body and touch rails use the same dock height. [Controller companion layout](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Compact portrait dock / application build 3.0.74

The dock centres its visible tab artwork in a shorter bottom plate. A small bottom strip is reserved for gestures. The middle artwork extends into the reclaimed height and shares its vertical transform with input. The touch rails use an even pitch for their main rows. [Companion layout details](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Centred portrait companion / application build 3.0.75

Companion content fits proportionally and centres above the compact dock. The dock palette uses display sRGB colours, with the authored icon shadow and dark selected labels. [Companion layout details](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

### Companion response and weather badge / application build 3.0.76

The companion reads the first published snapshot after a user action and gives the visible page priority in its bounded image queue. The Today weather art uses a circular badge. [Companion layout details](dm/games/01006F8002326000/README.md#controller-companion-layout-2026-11-04)

## Inputs and build

Supply your own game packages, console keys and matching update/DLC outside the source tree. No keys, game packages, game-derived dialogue overlays, resident save templates, player saves or ready-to-play IPA/Mac apps are included.

Use Apple Silicon macOS, Xcode and the documented dependencies. The 3.0.76 iOS build used Xcode 27.2, generic arm64 and minimum iOS 26. Historical Mac packaging used an Apple-m1 CPU baseline and minimum macOS 27. [Development guide](docs/development.md)

For the normal extraction/rewriter/shader preparation pipeline, run from this source root:

    python3 scripts/build_ipa_from_nsp.py /external/game-packages -k /external/keys/prod.keys --platform mac --keep-extracted --language zh-Hans

For standard unsigned iOS or native Mac packaging, select --platform ios or --platform mac-app. Consult the script's --help and [the packing guide](docs/development.md#the-packing-script-in-detail). Keep all generated files on the external build volume.

Generate the optional resident catalog with scripts/build_acnh_resident_catalog.py to include all eleven phrase languages. Use --help for the RomFS, template-source and output arguments. The script uses external game resources and the optional NHSE templates as inputs. Keep the generated files outside the repository and preserve NHSE's GPL notices with template-containing builds. [Pinned NHSE source at cb07454](https://github.com/kwsch/NHSE/tree/cb07454)

Before packaging with the resident manager enabled, generate and verify the starter-dialogue overlay:

    python3 scripts/build_acnh_starter_dialogue.py /external/game/RomFS /external/game/dialogue-overlay --report /external/game/dialogue-overlay.json --merged-romfs /external/game/dialogue-RomFS
    python3 scripts/build_acnh_starter_dialogue.py /external/game/dialogue-RomFS --verify

For the final unsigned iOS build, use dm/ios/tools/build_ipa.sh with GAME=01006F8002326000 and the external W, PATCHED, ROMFS, MSL_IOS, AOC, FONT_PY, DM_CONTROL_NACP, DM_RESIDENT_CATALOG and DM_RESIDENT_LICENSE inputs described in BUILD-ANIMALDUO-1.1.txt and the earlier BUILD files. ROMFS must point to the verified merged dialogue-RomFS, and DM_CONTROL_NACP to the original control metadata. Set DM_LANG=zh-Hans and DM_PSO_GPUS=none for the generic configuration. The catalog/license paths and game extraction remain external. The generated Gen directory is disposable; do not commit it.

For native Mac packaging, first build dm/host with GAME=01006F8002326000 and an Apple-m1 CPU baseline, then pass the verified merged RomFS, matching external patched modules/libraries/profile tables/fonts and add-on content to dm/mac/pack_app.py. Set --cloud-save-setup for the chooser flow. Review its --help for the required options. Ad-hoc Mac signing and unsigned iOS packaging are separate workflows.

The BUILD files describe earlier snapshots. The current build instructions and version settings are in the build guide. [Build guide](docs/BUILD.zh-CN.md)

## Validation

The 3.0.76 build passed the native action notification, interrupted image queue, iOS and Mac startup checks. [Source review](SOURCE-REVIEW.json)

The 3.0.75 build passed proportional geometry, touch mapping, native art palette and Mac startup checks. [Source review](SOURCE-REVIEW.json)

The 3.0.74 tests compared the visible dock margins, the middle artwork and the touch rails across four Mac Catalyst portrait fixtures. The unsigned iOS build and Mac startup regression completed. [Source review](SOURCE-REVIEW.json)

The 3.0.73 tests sampled the last visible dock row in a Mac Catalyst fixture, including rectangular and rounded window masks. They also checked tab placement with asymmetric safe areas and the physical-controller transition. The unsigned iOS build and Mac startup regression passed. [Source review](SOURCE-REVIEW.json)

The 3.0.72 tests exercised the SwiftUI backdrop with two synthetic theme fixtures and controller states, and used the real UIKit pad to check Y and A spacing and touch dispatch. The unsigned iOS build and Mac startup regression passed. [Source review](SOURCE-REVIEW.json)

The 3.0.71 checks covered portrait key spacing, touch dispatch, dock rendering, and the shared lower edge on a Mac Catalyst fixture with synthetic artwork and controller events. The unsigned iOS build and Mac startup regression passed. [Source review](SOURCE-REVIEW.json)

The 3.0.70 checks exercised portrait scaling in the actual UIKit preview and pad, including button presses and releases. The Mac Catalyst fixture used synthetic controller events and companion artwork. The Mac startup regression and unsigned iOS build also passed. [Source review](SOURCE-REVIEW.json)

The 3.0.69 portrait checks exercised the UIKit and SwiftUI views on a Mac Catalyst fixture with synthetic artwork and controller events, alongside the unsigned iOS build and the Mac startup regression. The iOS changes have yet to be verified on a physical device. [Source review](SOURCE-REVIEW.json)

The published 1.2 release uses the 3.0.68 runtime and build inputs. Local validation includes the unsigned iOS build, startup regression, a test-island slow-walk comparison and the earlier short-return LAN tests. Physical-device LAN recovery, cross-device iCloud transfer and a repeated-room loading incident remain open. [Source review](SOURCE-REVIEW.json) · [Game and validation notes](dm/games/01006F8002326000/README.md)

Hosted checks are reported per commit. [GitHub Actions](https://github.com/ShawndYang/AnimalDuo/actions)

## Dependencies and licenses

- Original nxnative: MIT; see LICENSE.
- Eden Duo companion module and authored flavor strings: GPL-3.0-or-later; the exact revisions and notices are in dm/third_party/eden_duo/UPSTREAM.json and NOTICES.txt.
- Eden Duo BC decoding: MPL-2.0; stb components retain their MIT/public-domain notices.
- Zstandard and the other vendored dependencies retain their individual licenses.
- Optional NHSE-generated templates: preserve the corresponding GPL source and license when distributing them.

See LICENSES.txt and the individual component notices. Companion-enabled combined builds are provided under GPL-3.0-or-later, with original component notices retained. The original MIT license must not be mistaken for a blanket license on third-party GPL/MPL components.

## Privacy

The initial public snapshot excluded private local Git history. Subsequent public commits and older source releases are retained; download main as a ZIP or use `git clone --depth 1` for the smaller current tree. It excludes historical test recordings, private paths contained in those recordings, player saves, cloud-folder bookmarks, signing profiles, personal credentials and locally generated game output. The upstream screenshot gallery is omitted to reduce downloads. Authored companion strings remain unchanged; no local player screenshots are added. Upstream author credits remain intact.

Debug symbols and the nested NHSE source ZIP are excluded; the dependency is identified by its public pinned source reference instead. Public upstream tool binaries remain byte-identical, including any upstream build metadata. The publication is a source project, not a distribution of Nintendo's game.

Publishing to a personal GitHub account still reveals that public account and its repository activity; source redaction cannot hide the repository owner's identity.
