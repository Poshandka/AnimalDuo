// Native-port local play-history provider. PIA exchanges the friends service's
// opaque 0x40-byte registration key even for LDN sessions (SwIPC friends 10700).
// These tokens identify native peers, not Nintendo network accounts. Recent
// encounters live for this process; Nintendo friends/presence remain offline.
#include "hle.h"
#include "hle_lan.h"

enum { HISTORY_USERS = 8, HISTORY_RECENT = 64 };
typedef struct { uint8_t uid[16], token[64]; } history_user;
typedef struct { uint8_t uid[16], token[64], mine[72], theirs[72]; uint64_t seen; } history_record;
static pthread_mutex_t history_lock = PTHREAD_MUTEX_INITIALIZER;
static history_user history_users[HISTORY_USERS];
static history_record history_records[HISTORY_RECENT];
static unsigned history_user_count, history_record_count;
static uint64_t history_sequence;
static const uint8_t history_magic[8] = {'N', 'X', 'P', 'H', 1, 0, 0, 0};

uint32_t dm_lan_history_key(void *out, const void *uid, unsigned local) {
    if (!dm_lan_enabled() || !(local & 0xff) || !out || !uid) return RES_FAIL;
    uint8_t present = 0; for (int i = 0; i < 16; i++) present |= ((const uint8_t *)uid)[i];
    if (!present) return RES_FAIL;
    pthread_mutex_lock(&history_lock);
    unsigned i; for (i = 0; i < history_user_count; i++) if (!memcmp(history_users[i].uid, uid, 16)) break;
    if (i == HISTORY_USERS) { pthread_mutex_unlock(&history_lock); return RES_FAIL; }
    if (i == history_user_count) {
        memcpy(history_users[i].uid, uid, 16);
        arc4random_buf(history_users[i].token, 64);
        memcpy(history_users[i].token, history_magic, sizeof history_magic);
        history_user_count++;
    }
    memcpy(out, history_users[i].token, 64);
    pthread_mutex_unlock(&history_lock); return RES_OK;
}

uint32_t dm_lan_history_add(const void *uid, const void *key, const void *mine, const void *theirs) {
    if (!dm_lan_enabled() || !key || !mine || !theirs || memcmp(key, history_magic, sizeof history_magic)) return RES_FAIL;
    pthread_mutex_lock(&history_lock);
    // Older SDK overloads omit Uid and use the application's local account.
    if (!uid && history_user_count) uid = history_users[0].uid;
    int known = 0;
    for (unsigned i = 0; uid && i < history_user_count; i++) if (!memcmp(uid, history_users[i].uid, 16)) known = 1;
    if (!known) { pthread_mutex_unlock(&history_lock); return RES_FAIL; }
    unsigned i; for (i = 0; i < history_record_count; i++)
        if (!memcmp(history_records[i].uid, uid, 16) && !memcmp(history_records[i].token, key, 64)) break;
    if (i == HISTORY_RECENT) {
        i = 0; for (unsigned j = 1; j < HISTORY_RECENT; j++) if (history_records[j].seen < history_records[i].seen) i = j;
    } else if (i == history_record_count) history_record_count++;
    history_record *r = &history_records[i];
    memcpy(r->uid, uid, 16); memcpy(r->token, key, 64);
    memcpy(r->mine, mine, 72); memcpy(r->theirs, theirs, 72); r->seen = ++history_sequence;
    pthread_mutex_unlock(&history_lock);
    if (getenv("DM_NET_LOG")) LOG("local play history: encounter recorded");
    return RES_OK;
}
