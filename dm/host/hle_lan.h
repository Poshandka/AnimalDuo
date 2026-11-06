// Horizon LDN ABI, documented by switchbrew/libnx nx/include/switch/services/ldn.h.
// The LAN transport is for native Apple ports; it does not speak the Switch radio protocol.
#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct { int64_t communication_id; uint8_t reserved[2]; uint16_t scene; uint8_t padding[4]; } dm_ldn_intent;
typedef struct { dm_ldn_intent intent; uint8_t session[16]; } dm_ldn_id;
typedef struct { uint8_t bytes[6]; } dm_ldn_mac;
typedef struct { uint8_t length; char text[33]; } dm_ldn_ssid;
typedef struct {
    dm_ldn_mac bssid; dm_ldn_ssid ssid; int16_t channel; int8_t signal;
    uint8_t type, reserved[4];
} dm_ldn_common;
typedef struct {
    uint32_t ip; dm_ldn_mac mac; int8_t id; uint8_t connected;
    char name[33]; uint8_t platform; int16_t version; uint8_t reserved[16];
} dm_ldn_node;
typedef struct {
    dm_ldn_id id; dm_ldn_common common; uint8_t server_random[16];
    uint16_t security_mode; uint8_t policy, version, reserved0[2]; int8_t capacity; uint8_t count;
    dm_ldn_node nodes[8]; uint8_t reserved1[2]; uint16_t advertise_size;
    uint8_t advertise[384], reserved2[140]; uint64_t reserved3;
} dm_ldn_info;
typedef struct { char name[33]; uint8_t reserved[15]; } dm_ldn_user;
typedef struct { uint16_t mode, size; uint8_t passphrase[64]; } dm_ldn_security;
typedef struct { uint8_t server_random[16], session[16]; } dm_ldn_secret;
typedef struct {
    dm_ldn_intent intent; int16_t channel; int8_t capacity; uint8_t reserved0;
    int16_t version; uint8_t reserved1[10];
} dm_ldn_config;
typedef struct {
    dm_ldn_id id; uint32_t type; dm_ldn_mac bssid; dm_ldn_ssid ssid;
    uint8_t reserved[16]; uint32_t flags;
} dm_ldn_filter;
typedef struct { uint8_t change, reserved[7]; } dm_ldn_update;
typedef struct { uint32_t ip; dm_ldn_mac mac; uint8_t reserved[2]; } dm_ldn_address;

_Static_assert(sizeof(dm_ldn_node) == 0x40, "LDN NodeInfo");
_Static_assert(sizeof(dm_ldn_info) == 0x480, "LDN NetworkInfo");
_Static_assert(offsetof(dm_ldn_info, nodes) == 0x68, "LDN nodes offset");
_Static_assert(offsetof(dm_ldn_info, advertise) == 0x26c, "LDN advertise offset");
_Static_assert(sizeof(dm_ldn_filter) == 0x60, "LDN ScanFilter");
_Static_assert(sizeof(dm_ldn_config) == 0x20, "LDN NetworkConfig");

enum { DM_LDN_NONE, DM_LDN_INIT, DM_LDN_AP, DM_LDN_HOST, DM_LDN_STATION, DM_LDN_CONNECTED, DM_LDN_ERROR };
// Native presentation only; this is separate from the Horizon LDN ABI above.
enum { DM_LAN_WAIT_NONE, DM_LAN_WAIT_PREPARING, DM_LAN_WAIT_PAUSED,
       DM_LAN_WAIT_RESUMING, DM_LAN_WAIT_ENDED };
typedef struct { int state, seconds, supported, local_background, settling; } dm_lan_wait_info;
int dm_lan_background(int background); // Scene background/foreground, not a temporary loss of focus.
void dm_lan_wait_snapshot(dm_lan_wait_info *out);
void dm_lan_wait_cancel(void);
void dm_lan_wait_guest(void);           // Guest data sockets pause; the native control plane stays alive.
enum { DM_LDN_BAD_STATE = (32 << 9) | 203, DM_LDN_BAD_ARGUMENT = (96 << 9) | 203,
       DM_LDN_NOT_FOUND = (48 << 9) | 203, DM_LDN_CONNECT_FAILED = (64 << 9) | 203 };

int dm_lan_enabled(void);
uint32_t dm_lan_ip(void);       // Network byte order, for BSD sockets / nifm.
uint32_t dm_lan_mask(void);     // LDN's own Ipv4Address/SubnetMask structs use host byte order.
int dm_lan_peer(uint32_t ip);
int dm_lan_peers(uint32_t *ips, int capacity);
int dm_lan_broadcast(uint32_t ip);
uint32_t dm_lan_history_key(void *, const void *, unsigned);
uint32_t dm_lan_history_add(const void *, const void *, const void *, const void *);
uint32_t dm_ldn_init(void);
void dm_ldn_finalize(void);
int dm_ldn_state(void);
uint32_t dm_ldn_open(int access_point);
uint32_t dm_ldn_close(int access_point);
uint32_t dm_ldn_create(const dm_ldn_config *, const dm_ldn_security *, const dm_ldn_secret *, const dm_ldn_user *, int, const dm_ldn_address *);
uint32_t dm_ldn_scan(dm_ldn_info *, int *, int, const dm_ldn_filter *, int, int);
uint32_t dm_ldn_connect(const dm_ldn_info *, const dm_ldn_security *, const dm_ldn_user *, int);
uint32_t dm_ldn_disconnect(int destroy);
uint32_t dm_ldn_info_get(dm_ldn_info *, dm_ldn_update *, int);
uint32_t dm_ldn_advertise(const void *, size_t);

void dm_nifm_set_local(int on);
int dm_nifm_local_available(void);
uint32_t dm_nifm_ip_config(uint32_t *, uint32_t *, uint32_t *, uint32_t *, uint32_t *);
void dm_nifm_submit_wait(void);
