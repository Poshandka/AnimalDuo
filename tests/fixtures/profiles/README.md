# Profile metadata fixtures

These small, unmodified upstream `game.tsv`, `patches.py` and `usage.tsv` files retain generic
build, patch-registry and packaging and usage-manifest regression coverage across NVN, Vulkan and
OpenGL. They are test inputs, not supported runtime profiles. The large shader
indices, game-specific capture tables and screenshots are deliberately omitted.

Tests opt in through `DM_GAMES_DIR` for the duration of a case. Production builds
only discover the Animal Crossing profile in `dm/games`; do not add this fixture
directory to your normal build environment. Full historical notes remain in
[upstream nxnative](https://github.com/seedds/nxnative/tree/b7a5cd43453722d448e07407d88a9c05ed294492/dm/games).
Original attribution and licenses are retained.
