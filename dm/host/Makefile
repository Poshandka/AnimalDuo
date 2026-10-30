# Game profile (dm/games/<id>/): the host is built for it (make GAME=base game title ID, required: there is no default game). game_profile.h is generated from game.tsv into gen/<id>/; the chain version header dmsh_chain.h (one for every game) lives in dm/gfx/nvn
# without GAME only clean passes; anything else (a bare make too, whose default goal is the host) stops and lists the profiles
ifeq ($(strip $(GAME)),)
ifneq ($(filter-out clean,$(or $(MAKECMDGOALS),dmhost)),)
$(error GAME is not set: make GAME=<base game title ID>: $(shell python3 ../games/game.py list | awk -F'\t' '{printf "%s (%s)  ", $$1, $$3}'))
endif
endif
# A profile outside the repository (DM_GAMES_DIR, e.g. the NSP script's provisional profile) is reached through the symlink gen/<id>/profile: make cannot take paths with spaces.
# DM_GAMES_FIRST=1 (the NSP script's --provisional) takes it even when dm/games has the game
ifneq ($(strip $(GAME)),)
GAME_DIR := $(if $(and $(wildcard ../games/$(GAME)/game.tsv),$(if $(DM_GAMES_FIRST),,1)),../games/$(GAME),$(shell python3 ../games/game.py link $(GAME) gen/$(GAME)/profile >&2 && echo gen/$(GAME)/profile))
ifeq ($(GAME_DIR),)
$(error no game profile $(GAME) (neither in dm/games nor in DM_GAMES_DIR))
endif
endif
GAME_H = gen/$(GAME)/game_profile.h
-include $(GAME_DIR)/companion.mk
CFLAGS=-O1 -g -Wall -Wno-unused-function
# Service-layer takeover hle_*.c files are included by wildcard: adding a file does not touch this line (avoids merge conflicts)
SRC=main.c loader.c hle.c crash.c probe.c thread.c memstat.m performance_apple.m haptics_apple.m save_sync_apple.m save_sync_mac.m $(sort $(wildcard hle_*.c)) front_mac.m entry.S $(COMPANION_C)
CXX_SRC=companion_apple.mm $(COMPANION_CXX)
CXX_HEADERS=$(wildcard ../third_party/eden_duo/acnh/*.h ../third_party/eden_duo/acnh/*.inc ../third_party/eden_duo/acnh/third_party/*.h ../third_party/eden_duo/core/mods/*.h ../third_party/eden_duo/core/mods/modules/*.h ../third_party/eden_duo/bc_decoder/*.h ../third_party/eden_duo/stb/*.h ../third_party/zstd/*.h ../third_party/zstd/common/*.h ../third_party/zstd/decompress/*.h) companion.h companion_apple.h
CXX_OBJ=$(foreach s,$(CXX_SRC),gen/companion/$(GAME)/$(notdir $(basename $(s))).o)
CXX_LIB=gen/companion/$(GAME)/libcompanion.a
COMPANION_DEFS=$(if $(COMPANION_CXX),-DDM_HAS_COMPANION=1,) -DZSTD_DISABLE_ASM=1 -DZSTD_LEGACY_SUPPORT=0
define companion_object
gen/companion/$(GAME)/$(notdir $(basename $(1))).o: $(1) $(CXX_HEADERS)
	@mkdir -p $$(dir $$@)
	clang++ -O2 -g -std=c++20 -fobjc-arc -ffp-contract=off -I../third_party/eden_duo $$(COMPANION_INCLUDES) $$(COMPANION_DEFS) -c $$< -o $$@
endef
$(foreach s,$(CXX_SRC),$(eval $(call companion_object,$(s))))
$(CXX_LIB): $(CXX_OBJ)
	rm -f $@; ar rcs $@ $^
# NVN null device + nn::vi + the Vulkan layer (dm/gfx/)
# Sources under dm/gfx, dm/gfx/nvn, dm/gfx/tex, dm/gfx/vk and dm/gfx/gl are included by wildcard (tests/ and metal/ do not go into the host): adding a file does not touch this line
GFX=$(sort $(wildcard ../gfx/*.c ../gfx/nvn/*.c ../gfx/nvn/*.m ../gfx/nvn/*.S ../gfx/tex/*.c ../gfx/tex/*.m ../gfx/vk/*.m ../gfx/gl/*.m))
GFX_H=$(sort $(wildcard ../gfx/nvn/*.h ../gfx/nvn/*.inc ../gfx/nvn/include/*.h ../gfx/tex/*.h))   # *.inc: nvn_mtl.m includes them (nvn_geometry.inc); an edit there alone used not to rebuild the host
# Third party: libvpx ships the VP8 and VP9 decoder sources (movie decoding, hle_movie.c), with its configuration headers in config/ (arm64, shared by Mac and iOS). Built separately into a static library, file by file, so host changes do not recompile it
VPX=../third_party/libvpx
VPX_SRC=$(sort $(shell find $(VPX) -name '*.c'))
VPX_OBJ=$(patsubst $(VPX)/%.c,gen/vpx/%.o,$(VPX_SRC))
VPX_LIB=gen/vpx/libvpx.a
gen/vpx/%.o: $(VPX)/%.c $(wildcard $(VPX)/config/*.h)
	@mkdir -p $(dir $@)
	clang -O2 -g -I$(VPX) -I$(VPX)/config -c $< -o $@
$(VPX_LIB): $(VPX_OBJ)
	rm -f $@; ar rcs $@ $^
.DEFAULT_GOAL := dmhost   # The header generation rules are written first below, so the default goal must be stated explicitly (otherwise make only generates the headers and does not build the host)
.PHONY: game_profile
game_profile: $(GAME_H)
# Regenerated on every make (FORCE): the same GAME can come from another profile folder (DM_GAMES_FIRST), whose game.tsv may be older than the header; game.py writes it only when it changes
$(GAME_H): $(GAME_DIR)/game.tsv ../games/game.py FORCE
	@python3 ../games/game.py header $(GAME) $@
# Records which game the host was built for: changing GAME changes the stamp's content and rebuilds the host (otherwise make sees dmhost as newer than both headers and keeps the other game's host).
# The game of the last build is also read when the Makefile is parsed, and a different one forces the link: make compares whole seconds, and a stamp written in the same second as
# another game's dmhost (two builds in a row) did not count as newer, so that game's host was kept
GAME_STAMP = gen/game.stamp
$(GAME_STAMP): FORCE
	@mkdir -p gen; echo $(GAME) | cmp -s - $@ || echo $(GAME) > $@
ifneq ($(strip $(GAME)),)
ifneq ($(shell cat $(GAME_STAMP) 2>/dev/null),$(GAME))
dmhost: FORCE
endif
endif
.PHONY: FORCE
FORCE:
dmhost: $(SRC) $(GFX) ../third_party/stb_vorbis/stb_vorbis.c dm.h hle.h hle_lan.h hle_socket.h dm_input.h pad_slots.h hle_haptics.h haptics_apple.h front.h $(GFX_H) $(GAME_H) $(GAME_STAMP) $(VPX_LIB) $(CXX_LIB)
	clang $(CFLAGS) $(COMPANION_INCLUDES) $(COMPANION_DEFS) -I../gfx/nvn/include -I../third_party/vulkan-headers/include -I$(dir $(GAME_H)) -I$(VPX) -I../third_party/stb_vorbis -fobjc-arc -o $@ $(SRC) $(GFX) $(VPX_LIB) $(CXX_LIB) -lc++ -framework Cocoa -framework QuartzCore -framework Metal -framework MetalFX -framework GameController -framework CoreHaptics -framework AudioToolbox -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework ImageIO -framework UniformTypeIdentifiers
clean:   # the host and everything make generates for it (gen/: the profile headers, the game stamp and the libvpx build; dmhost_* and *.dSYM beside them, as in .gitignore)
	rm -rf gen dmhost dmhost_* *.dSYM
.PHONY: clean
