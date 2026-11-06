# AnimalDuo public source

[简体中文构建说明](docs/BUILD.zh-CN.md) · [中文首页](README.md) · English

## Scope

This is a source snapshot of the Animal Crossing 3.0.3 Apple extension, based on nxnative revision b7a5cd43453722d448e07407d88a9c05ed294492. It preserves the original source and copyright notices. Runtime sources match application 3.0.59 (game 3.0.3); publication removes private records, unnecessary debug metadata and the nested dependency archive. The dedicated AnimalDuo tree also omits other games' large profile tables and the upstream screenshot gallery; their small, unchanged metadata and patch files survive only as opt-in test fixtures. The complete ACNH profile, runtime, dependencies and licenses are retained.

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

## AnimalDuo 1.1 / application build 3.0.59

This release adds expanded screen/UI and transition-mask coverage, 3D control migration,
controller companion layout, iPad half/full canvas adaptation and coordinated local-play
waiting. The host selects 30 seconds by default or 60 seconds; all members must support
waiting. Old builds keep ordinary LAN compatibility. iOS termination or a lost network
can still end a visit before the limit. See [the Chinese release notes](RELEASES/1.1.md).

VERSION contains the project release 1.1; APP_BUILD contains 3.0.59; game content remains
3.0.3. Thin updates can reuse compatible previously installed resources but cannot
bootstrap an installation. Absolute reverse-fold heading, intermittent room loading,
frame-time spikes, hours-long behavior and physical cross-device acceptance remain open.

## Inputs and build

Supply your own game packages, console keys and matching update/DLC outside the source tree. No keys, game packages, game-derived dialogue overlays, resident save templates, player saves or ready-to-play IPA/Mac apps are included.

Use Apple Silicon macOS, Xcode and the dependencies described in [the development guide](docs/development.md). The frozen 3.0.59 iOS release used Xcode 27.2, generic arm64 and minimum iOS 26. Historical Mac packaging used an Apple-m1 CPU baseline and minimum macOS 27. These are build settings, not a promise about other toolchain versions.

For the normal extraction/rewriter/shader preparation pipeline, run from this source root:

    python3 scripts/build_ipa_from_nsp.py /external/game-packages -k /external/keys/prod.keys --platform mac --keep-extracted --language zh-Hans

For standard unsigned iOS or native Mac packaging, select --platform ios or --platform mac-app. Consult the script's --help and [the packing guide](docs/development.md#the-packing-script-in-detail). Keep all generated files on the external build volume.

The optional resident catalog is generated with scripts/build_acnh_resident_catalog.py. Use --help for its RomFS, template-source and output arguments. Obtain the pinned [NHSE source at cb07454](https://github.com/kwsch/NHSE/tree/cb07454) separately and keep its generated templates outside the repository. No personal save is needed to generate that catalog. Preserve NHSE's GPL notices with any template-containing build.

Before packaging with the resident manager enabled, generate and verify the starter-dialogue overlay:

    python3 scripts/build_acnh_starter_dialogue.py /external/game/RomFS /external/game/dialogue-overlay --report /external/game/dialogue-overlay.json --merged-romfs /external/game/dialogue-RomFS
    python3 scripts/build_acnh_starter_dialogue.py /external/game/dialogue-RomFS --verify

For the final unsigned iOS build, use dm/ios/tools/build_ipa.sh with GAME=01006F8002326000 and the external W, PATCHED, ROMFS, MSL_IOS, AOC, FONT_PY, DM_CONTROL_NACP, DM_RESIDENT_CATALOG and DM_RESIDENT_LICENSE inputs described in BUILD-ANIMALDUO-1.1.txt and the earlier BUILD files. ROMFS must point to the verified merged dialogue-RomFS, and DM_CONTROL_NACP to the original control metadata. Set DM_LANG=zh-Hans and DM_PSO_GPUS=none for the generic configuration. The catalog/license paths and game extraction remain external. The generated Gen directory is disposable; do not commit it.

For native Mac packaging, first build dm/host with GAME=01006F8002326000 and an Apple-m1 CPU baseline, then pass the verified merged RomFS, matching external patched modules/libraries/profile tables/fonts and add-on content to dm/mac/pack_app.py. Set --cloud-save-setup for the chooser flow. Review its --help for the required options. Ad-hoc Mac signing and unsigned iOS packaging are separate workflows.

BUILD-ANIMALDUO-1.1.txt describes the current source; historical BUILD files describe earlier snapshots. Their references to private validation recordings are historical; those recordings are deliberately excluded from this public tree. Production unit-test sources remain available.

## Validation

The publication check verifies that production runtime and build-tool bytes match the input release, against the frozen 3.0.59 corresponding-source archive. Production code is unchanged by public-source preparation; existing lightweight test-fixture adaptations remain, with synthetic interface addresses normalized for publication. Documentation links and asset-independent unit checks are recorded in the accompanying publication report. Historical M4 measurements and unresolved issues are documented in [the game note](dm/games/01006F8002326000/README.md); they are not fresh device measurements from this publication.

Do not infer physical iPad/iPhone/M2, cross-device cloud/LAN, all-weather shader coverage or guaranteed prolonged stability from local Mac results. A repeated-room loading-readiness incident remains unresolved. Raw private run logs and screenshots are not needed to build this source.

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
