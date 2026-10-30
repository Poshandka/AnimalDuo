#include "../hle_lan_history.c"
#include "../hle_friends.c"
#include <assert.h>
static int enabled;
int dm_lan_enabled(void) { return enabled; }
void hle_bind_system_event(void *ev, int clear) { (void)ev; (void)clear; }
void hle_signal_system_event(void *ev) { (void)ev; }
static void *concurrent_history(void *unused) {
    (void)unused; uint8_t uid[16] = {1}, key[64], name[72] = {4};
    for (int i = 0; i < 1000; i++) { assert(!h_fr_GetPHKey(key, uid, 1)); assert(!h_fr_AddPlayHistory(key, name, name)); }
    return NULL;
}
int main(void) {
    uint8_t uid[16] = {1}, second[16] = {2}, zero[16] = {0};
    struct { uint8_t before, key[64], after; } out = {.before = 0x5a, .after = 0xa5};
    uint8_t again[64], peer[64], mine[72] = {1}, theirs[72] = {2};
    assert(h_fr_GetPHKey(out.key, uid, 1) != 0);
    enabled = 1;
    assert(h_fr_GetPHKey(out.key, uid, 0) != 0 && h_fr_GetPHKey(out.key, uid, 0x100) != 0);
    assert(h_fr_GetPHKey(out.key, zero, 1) != 0 && h_fr_GetPHKey(NULL, uid, 1) != 0);
    assert(!h_fr_GetPHKey(out.key, uid, 0x101) && out.before == 0x5a && out.after == 0xa5);
    assert(!h_fr_GetPHKey(again, uid, 1) && !memcmp(out.key, again, 64));
    assert(!h_fr_GetPHKey(peer, second, 1) && memcmp(out.key, peer, 64));
    assert(!h_fr_AddPlayHistory(peer, mine, theirs) && history_record_count == 1);
    mine[0] = 3; assert(!dm_lan_history_add(uid, peer, mine, theirs) && history_record_count == 1 && history_records[0].mine[0] == 3);
    peer[0] ^= 1; assert(dm_lan_history_add(uid, peer, mine, theirs) != 0); peer[0] ^= 1;
    for (int i = 0; i < 80; i++) { peer[63] = i; assert(!dm_lan_history_add(uid, peer, mine, theirs)); }
    assert(history_record_count == HISTORY_RECENT);
    pthread_t threads[4];
    for (int i = 0; i < 4; i++) assert(!pthread_create(&threads[i], NULL, concurrent_history, NULL));
    for (int i = 0; i < 4; i++) pthread_join(threads[i], NULL);
    enabled = 0; assert(dm_lan_history_add(uid, peer, mine, theirs) != 0);
    puts("Local play history: opaque tokens, offline policy, bounds, deduplication and eviction PASS");
    return 0;
}
