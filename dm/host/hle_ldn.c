// LDN sessions over a local IPv4 network between native ports. Bonjour carries the
// scan data; an authenticated TCP control connection carries membership changes.
// Game UDP/TCP payloads use the BSD adapter. No Nintendo/Internet service is used.
#include "hle.h"
#include "hle_lan.h"
#include <arpa/inet.h>
#include <CommonCrypto/CommonHMAC.h>
#include <dns_sd.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <poll.h>
#include <stdatomic.h>
#include <sys/socket.h>
#include <unistd.h>

#define LAN_SERVICE "_nxnative-ldn._tcp"
enum { LAN_VERSION = 1, LAN_MAX_DISCOVERED = 32, LAN_MAX_CLIENTS = 16,
       LAN_JOIN = 1, LAN_SNAPSHOT, LAN_PING, LAN_PONG, LAN_FAILURE, LAN_EXIT };
typedef struct { uint8_t magic[4]; uint16_t version, op; uint32_t size, result; } lan_header;
typedef struct { dm_ldn_node node; uint8_t session[16], proof[32]; } lan_join;
typedef struct { int fd, node; size_t have; uint8_t input[sizeof(lan_header) + sizeof(lan_join)]; uint64_t seen, opened; } lan_client;
typedef struct { int used, valid; char name[64]; DNSServiceRef resolver; uint32_t ip; uint16_t port; dm_ldn_info info; } lan_room;
static struct {
    pthread_mutex_t lock; pthread_cond_t changed; pthread_t thread;
    int running, stop, state, reason, listener, wake[2], station, drop_station, browse;
    uint16_t port; uint64_t revision, event; dm_ldn_mac mac;
    dm_ldn_info info; dm_ldn_config config; dm_ldn_security security;
    dm_ldn_update updates[8]; dm_ldn_mac filters[8]; int filter_count;
    lan_room rooms[LAN_MAX_DISCOVERED];
} lan = {.lock = PTHREAD_MUTEX_INITIALIZER, .changed = PTHREAD_COND_INITIALIZER,
         .listener = -1, .wake = {-1, -1}, .station = -1};
static pthread_mutex_t ip_lock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic uint32_t local_ip, local_mask;

int dm_lan_enabled(void) { const char *e = getenv("DM_LDN"); return e && atoi(e) != 0; }
static uint64_t lan_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000ull + t.tv_nsec / 1000000; }
static int private_ip(uint32_t ip) {
    uint32_t h = ntohl(ip);
    return (h >> 24) == 10 || (h >> 24) == 127 || (h >> 16) == 0xc0a8 ||
           (h & 0xfff00000) == 0xac100000 || (h >> 16) == 0xa9fe;
}
static void select_ip(void) {
    pthread_mutex_lock(&ip_lock);
    uint32_t ip = 0, mask = 0; const char *override = getenv("DM_LDN_BIND_IP");
    struct in_addr requested = {0};
    if (override && (!inet_pton(AF_INET, override, &requested) || !private_ip(requested.s_addr))) {
        LOG("[RED] ldn: DM_LDN_BIND_IP is not a local IPv4 address");
    } else {
        struct ifaddrs *all = NULL;
        if (!getifaddrs(&all)) {
            for (struct ifaddrs *p = all; p; p = p->ifa_next) {
                if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET || !(p->ifa_flags & IFF_UP)) continue;
                uint32_t a = ((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr;
                if (override ? a != requested.s_addr : (strncmp(p->ifa_name, "en", 2) || !private_ip(a))) continue;
                ip = a; mask = p->ifa_netmask ? ((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr : htonl(0xffffff00);
                break;
            }
            freeifaddrs(all);
        }
    }
    atomic_store(&local_ip, ip); atomic_store(&local_mask, mask);
    pthread_mutex_unlock(&ip_lock);
}
uint32_t dm_lan_ip(void) { if (!atomic_load(&local_ip)) select_ip(); return atomic_load(&local_ip); }
uint32_t dm_lan_mask(void) { return atomic_load(&local_mask); }
int dm_lan_broadcast(uint32_t ip) {
    uint32_t own = dm_lan_ip(), mask = dm_lan_mask();
    return ip == INADDR_BROADCAST || (own && mask && ip == (own | ~mask));
}
int dm_lan_peers(uint32_t *ips, int capacity) {
    int n = 0; uint32_t own = dm_lan_ip();
    pthread_mutex_lock(&lan.lock);
    if (lan.state == DM_LDN_HOST || lan.state == DM_LDN_CONNECTED)
        for (int i = 0; i < 8 && n < capacity; i++) if (lan.info.nodes[i].connected) {
            uint32_t ip = htonl(lan.info.nodes[i].ip);
            if (ip != own) ips[n++] = ip;
        }
    pthread_mutex_unlock(&lan.lock); return n;
}
int dm_lan_peer(uint32_t ip) { uint32_t peers[8]; int n = dm_lan_peers(peers, 8); for (int i = 0; i < n; i++) if (peers[i] == ip) return 1; return 0; }
static void wake_worker(void) { uint8_t b = 1; if (lan.wake[1] >= 0) (void)write(lan.wake[1], &b, 1); }
static void changed_locked(void) { lan.revision++; pthread_cond_broadcast(&lan.changed); }
static void signal_change(void) {
    pthread_mutex_lock(&lan.lock); uint64_t e = lan.event; pthread_mutex_unlock(&lan.lock);
    if (e) hle_signal_system_event_binding(e);
}
static void discovery_failed(int error) {
    LOG("[RED] ldn: Bonjour failed (%d); check Local Network permission", error);
    pthread_mutex_lock(&lan.lock);
    lan.state = DM_LDN_ERROR; lan.reason = 2; lan.browse = 0; changed_locked();
    pthread_mutex_unlock(&lan.lock); signal_change();
}
static void nonblock(int fd) { fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes); }
static int wait_fd(int fd, short events, uint64_t deadline) {
    for (;;) {
        uint64_t now = lan_ms(); if (now >= deadline) { errno = ETIMEDOUT; return -1; }
        struct pollfd p = {fd, events, 0};
        dm_thread_native_wait(1); int r = poll(&p, 1, (int)(deadline - now)); int e = errno; dm_thread_native_wait(0); errno = e;
        if (r > 0) return 0; if (r < 0 && errno == EINTR) continue; if (!r) errno = ETIMEDOUT; return -1;
    }
}
static int transfer(int fd, void *buf, size_t size, int sending, uint64_t deadline) {
    uint8_t *p = buf;
    while (size) {
        ssize_t n = sending ? send(fd, p, size, 0) : recv(fd, p, size, 0);
        if (n > 0) { p += n; size -= n; continue; }
        if (!n) return -1;
        if (errno == EINTR) continue;
        if ((errno == EAGAIN || errno == EWOULDBLOCK) && !wait_fd(fd, sending ? POLLOUT : POLLIN, deadline)) continue;
        return -1;
    }
    return 0;
}
static int send_frame(int fd, unsigned op, uint32_t result, const void *data, uint32_t size) {
    lan_header h = {{'N','X','L','D'}, LAN_VERSION, op, size, result}; uint64_t deadline = lan_ms() + 1000;
    return transfer(fd, &h, sizeof h, 1, deadline) || (size && transfer(fd, (void *)data, size, 1, deadline));
}
static int valid_header(const lan_header *h, uint32_t max) { return !memcmp(h->magic, "NXLD", 4) && h->version == LAN_VERSION && h->size <= max; }
static dm_ldn_node make_node(const dm_ldn_user *user, int version, dm_ldn_mac mac) {
    dm_ldn_node n = {0}; n.ip = ntohl(dm_lan_ip()); n.mac = mac; n.connected = 1; n.version = version;
    memcpy(n.name, user->name, 32); return n;
}
static void proof_for(const lan_join *j, const dm_ldn_security *security, uint8_t proof[32]) {
    CCHmac(kCCHmacAlgSHA256, security->passphrase, security->size, j, offsetof(lan_join, proof), proof);
}
static int same_mac(dm_ldn_mac a, dm_ldn_mac b) { return !memcmp(a.bytes, b.bytes, 6); }
static int valid_info(const dm_ldn_info *n) {
    if (n->capacity < 1 || n->capacity > 8 || !n->count || n->count > n->capacity || n->advertise_size > 384 || !n->nodes[0].connected) return 0;
    int count = 0;
    for (int i = 0; i < 8; i++) if (n->nodes[i].connected) {
        if (n->nodes[i].id != i || !private_ip(htonl(n->nodes[i].ip))) return 0;
        count++;
    }
    return count == n->count;
}
static void update_info_locked(const dm_ldn_info *info) {
    for (int i = 0; i < 8; i++) {
        if (lan.info.nodes[i].connected && (!info->nodes[i].connected || !same_mac(lan.info.nodes[i].mac, info->nodes[i].mac))) lan.updates[i].change |= 2;
        if (info->nodes[i].connected && (!lan.info.nodes[i].connected || !same_mac(lan.info.nodes[i].mac, info->nodes[i].mac))) lan.updates[i].change |= 1;
    }
    lan.info = *info; changed_locked();
}
static void remove_node(int node) {
    pthread_mutex_lock(&lan.lock);
    if (node > 0 && node < 8 && lan.info.nodes[node].connected) {
        lan.info.nodes[node].connected = 0; lan.info.count--; lan.updates[node].change |= 2; changed_locked();
        LOG("ldn: station %d left, %u node(s)", node, lan.info.count);
    }
    pthread_mutex_unlock(&lan.lock); signal_change();
}
static uint32_t accept_join(const lan_join *join, uint32_t peer_ip, int *node) {
    uint32_t result = DM_LDN_CONNECT_FAILED; uint8_t proof[32], difference = 0;
    pthread_mutex_lock(&lan.lock);
    if (lan.state != DM_LDN_HOST) { result = DM_LDN_BAD_STATE; goto end; }
    proof_for(join, &lan.security, proof);
    for (int i = 0; i < 32; i++) difference |= proof[i] ^ join->proof[i];
    if (difference || memcmp(join->session, lan.info.id.session, 16) || join->node.ip != ntohl(peer_ip) || join->node.version != lan.config.version) goto end;
    if (same_mac(join->node.mac, lan.mac) || !private_ip(peer_ip)) goto end;
    int listed = 0;
    for (int i = 0; i < lan.filter_count; i++) if (same_mac(join->node.mac, lan.filters[i])) listed = 1;
    int policy = lan.info.policy;
    if (policy == 1 || (policy == 2 && listed) || (policy == 3 && !listed)) goto end;
    for (int i = 1; i < 8; i++) if (lan.info.nodes[i].connected &&
        (same_mac(join->node.mac, lan.info.nodes[i].mac) || join->node.ip == lan.info.nodes[i].ip)) goto end;
    for (int i = 1; i < lan.info.capacity; i++) if (!lan.info.nodes[i].connected) {
        lan.info.nodes[i] = join->node; lan.info.nodes[i].id = i; lan.info.nodes[i].connected = 1; lan.info.count++;
        lan.updates[i].change |= 1; *node = i; changed_locked(); result = RES_OK;
        LOG("ldn: station %d joined, %u node(s)", i, lan.info.count); break;
    }
end:
    pthread_mutex_unlock(&lan.lock); if (!result) signal_change(); return result;
}
// All DNSServiceRef objects and TCP control streams below belong to this worker.
static void publish_reply(DNSServiceRef ref, DNSServiceFlags flags, DNSServiceErrorType error, const char *name, const char *type, const char *domain, void *context) {
    (void)ref; (void)flags; (void)name; (void)type; (void)domain; (void)context;
    if (error) discovery_failed(error);
    else LOG("ldn: room published on the local network");
}
static int make_txt(TXTRecordRef *txt, const dm_ldn_info *info) {
    TXTRecordCreate(txt, 0, NULL); uint8_t version = LAN_VERSION; uint32_t ip = dm_lan_ip();
    if (TXTRecordSetValue(txt, "v", 1, &version) || TXTRecordSetValue(txt, "ip", 4, &ip)) return -1;
    for (int i = 0; i < 6; i++) { char key[4]; snprintf(key, sizeof key, "n%d", i); if (TXTRecordSetValue(txt, key, 192, (const uint8_t *)info + i * 192)) return -1; }
    return 0;
}
static void resolve_reply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface, DNSServiceErrorType error,
                          const char *name, const char *target, uint16_t port, uint16_t length, const unsigned char *txt, void *context) {
    (void)ref; (void)flags; (void)interface; (void)name; (void)target; lan_room *room = context;
    if (error) { pthread_mutex_lock(&lan.lock); room->valid = 0; pthread_mutex_unlock(&lan.lock); return; }
    dm_ldn_info info; uint8_t size = 0;
    const uint8_t *version = TXTRecordGetValuePtr(length, txt, "v", &size);
    if (!version || size != 1 || *version != LAN_VERSION) return;
    const void *ip_ptr = TXTRecordGetValuePtr(length, txt, "ip", &size); uint32_t ip;
    if (!ip_ptr || size != 4) return; memcpy(&ip, ip_ptr, 4);
    for (int i = 0; i < 6; i++) {
        char key[4]; snprintf(key, sizeof key, "n%d", i); const void *p = TXTRecordGetValuePtr(length, txt, key, &size);
        if (!p || size != 192) return; memcpy((uint8_t *)&info + i * 192, p, 192);
    }
    if (!valid_info(&info) || ip != htonl(info.nodes[0].ip) || same_mac(info.nodes[0].mac, lan.mac)) return;
    pthread_mutex_lock(&lan.lock); room->ip = ip; room->port = ntohs(port); room->info = info; room->valid = 1;
    pthread_cond_broadcast(&lan.changed); pthread_mutex_unlock(&lan.lock);
}
static void browse_reply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface, DNSServiceErrorType error,
                         const char *name, const char *type, const char *domain, void *context) {
    (void)ref; (void)context;
    if (error) { discovery_failed(error); return; }
    lan_room *room = NULL;
    pthread_mutex_lock(&lan.lock);
    for (int i = 0; i < LAN_MAX_DISCOVERED; i++) if (lan.rooms[i].used && !strcmp(lan.rooms[i].name, name)) { room = &lan.rooms[i]; break; }
    if (!(flags & kDNSServiceFlagsAdd)) {
        if (room) { room->valid = 0; room->used = 0; if (room->resolver) { DNSServiceRefDeallocate(room->resolver); room->resolver = NULL; } }
        pthread_mutex_unlock(&lan.lock); return;
    }
    if (!room) for (int i = 0; i < LAN_MAX_DISCOVERED; i++) if (!lan.rooms[i].used) { room = &lan.rooms[i]; memset(room, 0, sizeof *room); room->used = 1; snprintf(room->name, sizeof room->name, "%s", name); break; }
    pthread_mutex_unlock(&lan.lock);
    if (room && !room->resolver) {
        DNSServiceErrorType r = DNSServiceResolve(&room->resolver, 0, interface, name, type, domain, resolve_reply, room);
        if (r) LOG("[RED] ldn: Bonjour room resolve failed (%d)", r);
    }
}
static void station_lost(int reason) {
    pthread_mutex_lock(&lan.lock);
    if (lan.state == DM_LDN_CONNECTED) { lan.state = DM_LDN_STATION; lan.reason = reason; memset(&lan.info, 0, sizeof lan.info); changed_locked(); }
    pthread_mutex_unlock(&lan.lock); signal_change();
}
static void *lan_worker(void *unused) {
    (void)unused; DNSServiceRef registration = NULL, browser = NULL;
    lan_client clients[LAN_MAX_CLIENTS]; for (int i = 0; i < LAN_MAX_CLIENTS; i++) clients[i].fd = -1;
    uint64_t published = 0, sent = 0, last_ping = 0, station_seen = lan_ms(); size_t station_have = 0; int tracked_station = -1;
    uint8_t station_input[sizeof(lan_header) + sizeof(dm_ldn_info)];
    for (;;) {
        pthread_mutex_lock(&lan.lock);
        int stop = lan.stop, state = lan.state, browsing = lan.browse, station = lan.station;
        int drop = lan.drop_station; lan.drop_station = 0;
        uint64_t revision = lan.revision; dm_ldn_info info = lan.info;
        if (drop && station >= 0) { lan.station = -1; station_have = 0; }
        pthread_mutex_unlock(&lan.lock);
        if (stop) break;
        if (drop && station >= 0) { close(station); station = -1; }
        if (station != tracked_station) { tracked_station = station; station_seen = lan_ms(); station_have = 0; }
        if (state != DM_LDN_HOST) {
            if (registration) { DNSServiceRefDeallocate(registration); registration = NULL; published = 0; }
            for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0) {
                if (clients[i].node > 0) send_frame(clients[i].fd, LAN_EXIT, 3, NULL, 0);
                close(clients[i].fd); clients[i].fd = -1;
            }
        } else if (revision != published) {
            TXTRecordRef txt;
            if (!make_txt(&txt, &info)) {
                DNSServiceErrorType r;
                if (!registration) {
                    char name[64]; snprintf(name, sizeof name, "nx-%02x%02x%02x%02x%02x%02x", lan.mac.bytes[0], lan.mac.bytes[1], lan.mac.bytes[2], lan.mac.bytes[3], lan.mac.bytes[4], lan.mac.bytes[5]);
                    r = DNSServiceRegister(&registration, 0, 0, name, LAN_SERVICE, NULL, NULL, htons(lan.port), TXTRecordGetLength(&txt), TXTRecordGetBytesPtr(&txt), publish_reply, NULL);
                } else r = DNSServiceUpdateRecord(registration, NULL, 0, TXTRecordGetLength(&txt), TXTRecordGetBytesPtr(&txt), 0);
                if (r) discovery_failed(r);
                published = revision;
            }
            TXTRecordDeallocate(&txt);
        }
        if (!browsing && browser) { DNSServiceRefDeallocate(browser); browser = NULL; }
        if (browsing && !browser) {
            DNSServiceErrorType r = DNSServiceBrowse(&browser, 0, 0, LAN_SERVICE, NULL, browse_reply, NULL);
            if (r) discovery_failed(r);
        }
        if (state == DM_LDN_HOST && revision != sent) {
            for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0 && clients[i].node > 0) {
                pthread_mutex_lock(&lan.lock); int connected = lan.info.nodes[clients[i].node].connected; pthread_mutex_unlock(&lan.lock);
                if (!connected) send_frame(clients[i].fd, LAN_EXIT, 5, NULL, 0);
                if (!connected || send_frame(clients[i].fd, LAN_SNAPSHOT, 0, &info, sizeof info)) { close(clients[i].fd); clients[i].fd = -1; if (connected) remove_node(clients[i].node); }
            }
            sent = revision;
        }
        uint64_t now = lan_ms();
        if (now - last_ping >= 2000) {
            last_ping = now;
            for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0) {
                if ((clients[i].node < 0 && now - clients[i].opened > 5000) || now - clients[i].seen > 10000 ||
                    (clients[i].node > 0 && send_frame(clients[i].fd, LAN_PING, 0, NULL, 0))) {
                    close(clients[i].fd); clients[i].fd = -1; remove_node(clients[i].node);
                }
            }
            if (station >= 0 && (now - station_seen > 10000 || send_frame(station, LAN_PING, 0, NULL, 0))) {
                pthread_mutex_lock(&lan.lock); if (lan.station == station) { close(station); lan.station = -1; } pthread_mutex_unlock(&lan.lock);
                station = -1; station_have = 0; station_lost(6);
            }
        }
        struct pollfd pf[2 + 2 + LAN_MAX_DISCOVERED + LAN_MAX_CLIENTS + 1]; DNSServiceRef refs[sizeof pf / sizeof pf[0]];
        int kinds[sizeof pf / sizeof pf[0]], indices[sizeof pf / sizeof pf[0]], count = 0;
        #define WATCH(fd_, kind_, index_, ref_) do { if ((fd_) >= 0) { pf[count] = (struct pollfd){(fd_), POLLIN, 0}; kinds[count] = kind_; indices[count] = index_; refs[count] = ref_; count++; } } while (0)
        WATCH(lan.wake[0], 0, 0, NULL); WATCH(lan.listener, 1, 0, NULL);
        if (registration) WATCH(DNSServiceRefSockFD(registration), 2, 0, registration);
        if (browser) WATCH(DNSServiceRefSockFD(browser), 2, 0, browser);
        for (int i = 0; i < LAN_MAX_DISCOVERED; i++) if (lan.rooms[i].resolver) WATCH(DNSServiceRefSockFD(lan.rooms[i].resolver), 3, i, lan.rooms[i].resolver);
        for (int i = 0; i < LAN_MAX_CLIENTS; i++) WATCH(clients[i].fd, 4, i, NULL);
        WATCH(station, 5, 0, NULL);
        #undef WATCH
        if (poll(pf, count, 1000) <= 0) continue;
        for (int k = 0; k < count; k++) if (pf[k].revents) {
            if (!kinds[k]) { uint8_t bytes[64]; while (read(lan.wake[0], bytes, sizeof bytes) > 0) {} }
            else if (kinds[k] == 1) {
                for (;;) {
                    int fd = accept(lan.listener, NULL, NULL); if (fd < 0) break; nonblock(fd);
                    int placed = 0;
                    if (state == DM_LDN_HOST) for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd < 0) {
                        clients[i] = (lan_client){.fd = fd, .node = -1, .seen = lan_ms(), .opened = lan_ms()}; placed = 1; break;
                    }
                    if (!placed) close(fd);
                }
            } else if (kinds[k] == 2 || kinds[k] == 3) {
                if (kinds[k] == 3 && (lan.rooms[indices[k]].resolver != refs[k] || DNSServiceRefSockFD(refs[k]) != pf[k].fd)) continue;
                DNSServiceErrorType r = DNSServiceProcessResult(refs[k]);
                if (r) {
                    DNSServiceRefDeallocate(refs[k]);
                    if (kinds[k] == 3) {
                        pthread_mutex_lock(&lan.lock); lan.rooms[indices[k]].resolver = NULL; lan.rooms[indices[k]].valid = 0; pthread_mutex_unlock(&lan.lock);
                    } else {
                        if (refs[k] == registration) registration = NULL;
                        if (refs[k] == browser) browser = NULL;
                        discovery_failed(r);
                    }
                }
            } else if (kinds[k] == 4) {
                lan_client *c = &clients[indices[k]]; if (c->fd != pf[k].fd) continue;
                ssize_t n = recv(c->fd, c->input + c->have, sizeof c->input - c->have, 0);
                if (n <= 0) { if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue; close(c->fd); c->fd = -1; remove_node(c->node); continue; }
                c->have += n; c->seen = lan_ms();
                while (c->fd >= 0 && c->have >= sizeof(lan_header)) {
                    lan_header h; memcpy(&h, c->input, sizeof h);
                    if (!valid_header(&h, sizeof(lan_join))) { close(c->fd); c->fd = -1; remove_node(c->node); break; }
                    size_t frame_size = sizeof h + h.size; if (c->have < frame_size) break;
                    if (h.op == LAN_JOIN && h.size == sizeof(lan_join) && c->node < 0) {
                        lan_join join; memcpy(&join, c->input + sizeof h, sizeof join);
                        struct sockaddr_in peer = {0}; socklen_t size = sizeof peer; getpeername(c->fd, (struct sockaddr *)&peer, &size);
                        uint32_t result = accept_join(&join, peer.sin_addr.s_addr, &c->node);
                        if (result) { send_frame(c->fd, LAN_FAILURE, result, NULL, 0); close(c->fd); c->fd = -1; }
                    } else if (h.op == LAN_PING && !h.size) send_frame(c->fd, LAN_PONG, 0, NULL, 0);
                    else if (h.op != LAN_PONG || h.size) { close(c->fd); c->fd = -1; remove_node(c->node); }
                    c->have -= frame_size; memmove(c->input, c->input + frame_size, c->have);
                }
            } else if (kinds[k] == 5) {
                ssize_t n = recv(station, station_input + station_have, sizeof station_input - station_have, 0);
                int lost = n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR), lost_reason = 6;
                if (n > 0) { station_have += n; station_seen = lan_ms(); }
                while (!lost && station_have >= sizeof(lan_header)) {
                    lan_header h; memcpy(&h, station_input, sizeof h);
                    if (!valid_header(&h, sizeof(dm_ldn_info))) { lost = 1; break; }
                    size_t size = sizeof h + h.size; if (station_have < size) break;
                    if (h.op == LAN_SNAPSHOT && h.size == sizeof(dm_ldn_info)) {
                        dm_ldn_info next; memcpy(&next, station_input + sizeof h, sizeof next);
                        pthread_mutex_lock(&lan.lock);
                        if (!valid_info(&next) || memcmp(&next.id, &lan.info.id, sizeof next.id)) lost = 1;
                        else if (lan.state == DM_LDN_CONNECTED) update_info_locked(&next);
                        pthread_mutex_unlock(&lan.lock); signal_change();
                    } else if (h.op == LAN_EXIT && !h.size) { lost = 1; lost_reason = h.result >= 1 && h.result <= 6 ? h.result : 2; }
                    else if (h.op == LAN_PING && !h.size) send_frame(station, LAN_PONG, 0, NULL, 0);
                    else if (h.op != LAN_PONG || h.size) lost = 1;
                    station_have -= size; memmove(station_input, station_input + size, station_have);
                }
                if (lost) {
                    pthread_mutex_lock(&lan.lock); if (lan.station == station) { close(station); lan.station = -1; } pthread_mutex_unlock(&lan.lock);
                    station = -1; station_have = 0; station_lost(lost_reason);
                }
            }
        }
    }
    if (registration) DNSServiceRefDeallocate(registration); if (browser) DNSServiceRefDeallocate(browser);
    for (int i = 0; i < LAN_MAX_DISCOVERED; i++) if (lan.rooms[i].resolver) { DNSServiceRefDeallocate(lan.rooms[i].resolver); lan.rooms[i].resolver = NULL; }
    pthread_mutex_lock(&lan.lock); int exit_reason = lan.reason == 3 ? 3 : 4; pthread_mutex_unlock(&lan.lock);
    for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0) {
        if (clients[i].node > 0) send_frame(clients[i].fd, LAN_EXIT, exit_reason, NULL, 0);
        close(clients[i].fd);
    }
    pthread_mutex_lock(&lan.lock); if (lan.station >= 0) { close(lan.station); lan.station = -1; } pthread_mutex_unlock(&lan.lock);
    return NULL;
}

uint32_t dm_ldn_init(void) {
    if (!dm_lan_enabled()) return RES_FAIL;
    pthread_mutex_lock(&lan.lock);
    if (lan.running) { pthread_mutex_unlock(&lan.lock); return RES_OK; }
    select_ip(); uint32_t ip = dm_lan_ip();
    if (!ip) { pthread_mutex_unlock(&lan.lock); LOG("[RED] ldn: no local IPv4 interface available"); return RES_FAIL; }
    int fd = socket(AF_INET, SOCK_STREAM, 0); struct sockaddr_in address = {.sin_len = sizeof address, .sin_family = AF_INET, .sin_addr.s_addr = ip};
    if (fd < 0 || bind(fd, (void *)&address, sizeof address) || listen(fd, 16) || pipe(lan.wake)) {
        if (fd >= 0) close(fd); pthread_mutex_unlock(&lan.lock); return RES_FAIL;
    }
    socklen_t length = sizeof address; getsockname(fd, (void *)&address, &length);
    lan.listener = fd; lan.port = ntohs(address.sin_port); nonblock(fd); nonblock(lan.wake[0]); nonblock(lan.wake[1]);
    arc4random_buf(lan.mac.bytes, 6); lan.mac.bytes[0] = (lan.mac.bytes[0] | 2) & ~1;
    lan.stop = 0; lan.reason = 0; lan.state = DM_LDN_INIT; lan.event = 0; lan.browse = 0; lan.drop_station = 0; lan.filter_count = 0;
    memset(lan.rooms, 0, sizeof lan.rooms); memset(&lan.info, 0, sizeof lan.info); memset(lan.updates, 0, sizeof lan.updates); changed_locked();
    int error = pthread_create(&lan.thread, NULL, lan_worker, NULL);
    if (error) { close(fd); close(lan.wake[0]); close(lan.wake[1]); lan.listener = lan.wake[0] = lan.wake[1] = -1; lan.state = DM_LDN_NONE; pthread_mutex_unlock(&lan.lock); return RES_FAIL; }
    lan.running = 1; pthread_mutex_unlock(&lan.lock);
    struct in_addr a = {.s_addr = ip}; LOG("ldn: local multiplayer ready at %s:%u (native-port protocol %d)", inet_ntoa(a), lan.port, LAN_VERSION);
    return RES_OK;
}
void dm_ldn_finalize(void) {
    if (getenv("DM_NET_TRACE")) LOG("ldn: finalize");
    pthread_mutex_lock(&lan.lock); if (!lan.running) { pthread_mutex_unlock(&lan.lock); return; }
    lan.stop = 1; pthread_mutex_unlock(&lan.lock); wake_worker(); dm_host_thread_join(lan.thread, NULL);
    pthread_mutex_lock(&lan.lock); close(lan.listener); close(lan.wake[0]); close(lan.wake[1]);
    lan.listener = lan.wake[0] = lan.wake[1] = -1; lan.running = 0; lan.state = DM_LDN_NONE; changed_locked(); pthread_mutex_unlock(&lan.lock); signal_change();
}
int dm_ldn_state(void) { pthread_mutex_lock(&lan.lock); int s = lan.state; pthread_mutex_unlock(&lan.lock); if (getenv("DM_NET_TRACE")) LOG("ldn: state %d", s); return s; }
uint32_t dm_ldn_open(int ap) {
    pthread_mutex_lock(&lan.lock); uint32_t result = DM_LDN_BAD_STATE;
    if (lan.state == DM_LDN_INIT) { lan.state = ap ? DM_LDN_AP : DM_LDN_STATION; changed_locked(); result = 0; }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); if (getenv("DM_NET_TRACE")) LOG("ldn: open %s -> %#x", ap ? "host" : "station", result); return result;
}
uint32_t dm_ldn_close(int ap) {
    pthread_mutex_lock(&lan.lock); uint32_t result = DM_LDN_BAD_STATE;
    if (lan.state == (ap ? DM_LDN_AP : DM_LDN_STATION)) { lan.state = DM_LDN_INIT; changed_locked(); result = 0; }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); if (getenv("DM_NET_TRACE")) LOG("ldn: close %s -> %#x", ap ? "host" : "station", result); return result;
}
static void normalize_intent(dm_ldn_intent *id) { if (id->communication_id == -1) id->communication_id = DM_GAME_PROGRAM_ID; }
uint32_t dm_ldn_create(const dm_ldn_config *config, const dm_ldn_security *security, const dm_ldn_secret *secret, const dm_ldn_user *user, int count, const dm_ldn_address *addresses) {
    if (!config || !security || !user || config->capacity < 1 || config->capacity > 8 || config->version < 0 || security->size < 16 || security->size > 64 || count < 0 || count > 8 || (count && !addresses)) return DM_LDN_BAD_ARGUMENT;
    pthread_mutex_lock(&lan.lock); if (lan.state != DM_LDN_AP) { pthread_mutex_unlock(&lan.lock); return DM_LDN_BAD_STATE; }
    dm_ldn_info info = {0}; info.id.intent = config->intent; normalize_intent(&info.id.intent);
    arc4random_buf(info.id.session, 16); arc4random_buf(info.server_random, 16);
    if (secret) { memcpy(info.id.session, secret->session, 16); memcpy(info.server_random, secret->server_random, 16); }
    info.common.bssid = lan.mac; info.common.channel = config->channel ? config->channel : 1; info.common.signal = 3; info.common.type = 2;
    info.common.ssid.length = 32; for (int i = 0; i < 16; i++) snprintf(info.common.ssid.text + i * 2, 3, "%02x", info.id.session[i]);
    info.security_mode = 1; info.version = 2; info.capacity = config->capacity; info.count = 1; info.policy = lan.info.policy;
    info.advertise_size = lan.info.advertise_size; memcpy(info.advertise, lan.info.advertise, sizeof info.advertise);
    info.nodes[0] = make_node(user, config->version, lan.mac); lan.config = *config; normalize_intent(&lan.config.intent); lan.security = *security;
    lan.filter_count = count; for (int i = 0; i < count; i++) lan.filters[i] = addresses[i].mac;
    update_info_locked(&info); lan.state = DM_LDN_HOST; lan.reason = 0;
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); LOG("ldn: room created, capacity %d, communication version %d", config->capacity, config->version); return RES_OK;
}
static int matches(const dm_ldn_info *info, const dm_ldn_filter *filter, int channel) {
    dm_ldn_intent intent = filter->id.intent; normalize_intent(&intent); uint32_t f = filter->flags;
    return (!channel || channel == info->common.channel) &&
        (!(f & 1) || intent.communication_id == info->id.intent.communication_id) &&
        (!(f & 2) || !memcmp(filter->id.session, info->id.session, 16)) &&
        (!(f & 4) || (filter->type & info->common.type)) &&
        (!(f & 8) || same_mac(filter->bssid, info->common.bssid)) &&
        (!(f & 16) || (filter->ssid.length == info->common.ssid.length && filter->ssid.length <= 32 &&
                      !memcmp(filter->ssid.text, info->common.ssid.text, filter->ssid.length))) &&
        (!(f & 32) || intent.scene == info->id.intent.scene);
}
uint32_t dm_ldn_scan(dm_ldn_info *out, int *count, int capacity, const dm_ldn_filter *filter, int channel, int private_scan) {
    if (!count || capacity < 0 || capacity > 64 || (capacity && !out) || !filter || (filter->flags & ~63u)) return DM_LDN_BAD_ARGUMENT;
    *count = 0; pthread_mutex_lock(&lan.lock);
    if (!lan.running || lan.state == DM_LDN_ERROR) { pthread_mutex_unlock(&lan.lock); return DM_LDN_BAD_STATE; }
    lan.browse = 1; pthread_mutex_unlock(&lan.lock); wake_worker();
    struct timespec deadline; clock_gettime(CLOCK_REALTIME, &deadline); deadline.tv_sec++;
    pthread_mutex_lock(&lan.lock);
    for (;;) {
        int n = 0;
        dm_ldn_filter effective = *filter; if (!private_scan) effective.flags &= ~8u;
        for (int i = 0; i < LAN_MAX_DISCOVERED && n < capacity; i++) if (lan.rooms[i].valid && matches(&lan.rooms[i].info, &effective, channel)) out[n++] = lan.rooms[i].info;
        if (n || !capacity || !lan.running || lan.state == DM_LDN_ERROR) { *count = n; break; }
        dm_thread_native_wait(1); int r = pthread_cond_timedwait(&lan.changed, &lan.lock, &deadline); dm_thread_native_wait(0);
        if (r == ETIMEDOUT) break;
    }
    uint32_t result = lan.state == DM_LDN_ERROR ? DM_LDN_BAD_STATE : RES_OK;
    pthread_mutex_unlock(&lan.lock); LOG("ldn: scan found %d room(s)", *count); return result;
}
uint32_t dm_ldn_connect(const dm_ldn_info *info, const dm_ldn_security *security, const dm_ldn_user *user, int version) {
    if (!info || !valid_info(info) || !security || security->size < 16 || security->size > 64 || !user || version < 0 || version > INT16_MAX) return DM_LDN_BAD_ARGUMENT;
    uint16_t port = 0; uint32_t ip = 0; dm_ldn_mac mac;
    pthread_mutex_lock(&lan.lock);
    if (lan.state != DM_LDN_STATION) { pthread_mutex_unlock(&lan.lock); return DM_LDN_BAD_STATE; }
    for (int i = 0; i < LAN_MAX_DISCOVERED; i++) if (lan.rooms[i].valid && !memcmp(&lan.rooms[i].info.id, &info->id, sizeof info->id)) { port = lan.rooms[i].port; ip = lan.rooms[i].ip; break; }
    mac = lan.mac; pthread_mutex_unlock(&lan.lock); if (!port || !ip) return DM_LDN_NOT_FOUND;
    int fd = socket(AF_INET, SOCK_STREAM, 0); if (fd < 0) return RES_FAIL; nonblock(fd);
    struct sockaddr_in local = {.sin_len = sizeof local, .sin_family = AF_INET, .sin_addr.s_addr = dm_lan_ip()};
    struct sockaddr_in remote = {.sin_len = sizeof remote, .sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = ip};
    uint32_t result = RES_FAIL; uint64_t deadline = lan_ms() + 3000;
    if (bind(fd, (void *)&local, sizeof local)) goto end;
    if (connect(fd, (void *)&remote, sizeof remote) && (errno != EINPROGRESS || wait_fd(fd, POLLOUT, deadline))) goto end;
    int error = 0; socklen_t elen = sizeof error; if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &elen) || error) goto end;
    lan_join join = {0}; join.node = make_node(user, version, mac); memcpy(join.session, info->id.session, 16); proof_for(&join, security, join.proof);
    if (send_frame(fd, LAN_JOIN, 0, &join, sizeof join)) goto end;
    lan_header h; if (transfer(fd, &h, sizeof h, 0, deadline) || !valid_header(&h, sizeof(dm_ldn_info))) goto end;
    if (h.op == LAN_FAILURE && !h.size) { result = h.result ? h.result : DM_LDN_CONNECT_FAILED; goto end; }
    dm_ldn_info snapshot;
    if (h.op != LAN_SNAPSHOT || h.size != sizeof snapshot || transfer(fd, &snapshot, sizeof snapshot, 0, deadline) || !valid_info(&snapshot) || memcmp(&snapshot.id, &info->id, sizeof info->id)) goto end;
    int found = 0; for (int i = 1; i < 8; i++) if (snapshot.nodes[i].connected && same_mac(snapshot.nodes[i].mac, lan.mac)) found = 1;
    if (!found) goto end;
    pthread_mutex_lock(&lan.lock);
    if (lan.state == DM_LDN_STATION && lan.running && !lan.stop && lan.station < 0) {
        lan.station = fd; fd = -1; update_info_locked(&snapshot); lan.state = DM_LDN_CONNECTED; lan.reason = 0; result = 0;
    }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change();
end:
    if (fd >= 0) close(fd);
    LOG("ldn: connect %s (result %#x)", result ? "failed" : "complete", result); return result;
}
uint32_t dm_ldn_disconnect(int destroy) {
    pthread_mutex_lock(&lan.lock); uint32_t result = DM_LDN_BAD_STATE;
    if (lan.state == (destroy ? DM_LDN_HOST : DM_LDN_CONNECTED)) {
        lan.state = destroy ? DM_LDN_AP : DM_LDN_STATION; lan.reason = destroy ? 3 : 1; lan.drop_station = !destroy;
        memset(&lan.info, 0, sizeof lan.info); changed_locked(); result = 0;
    }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); if (getenv("DM_NET_TRACE")) LOG("ldn: %s -> %#x", destroy ? "destroy" : "disconnect", result); return result;
}
uint32_t dm_ldn_info_get(dm_ldn_info *out, dm_ldn_update *updates, int capacity) {
    if (!out || capacity < 0 || capacity > 8 || (capacity && !updates)) return DM_LDN_BAD_ARGUMENT;
    pthread_mutex_lock(&lan.lock);
    if (lan.state != DM_LDN_HOST && lan.state != DM_LDN_CONNECTED) { int s = lan.state; pthread_mutex_unlock(&lan.lock); if (getenv("DM_NET_TRACE")) LOG("ldn: network info in state %d -> bad state", s); return DM_LDN_BAD_STATE; }
    *out = lan.info;
    if (updates) { memcpy(updates, lan.updates, capacity * sizeof *updates); memset(lan.updates, 0, capacity * sizeof *updates); }
    pthread_mutex_unlock(&lan.lock); if (getenv("DM_NET_TRACE")) LOG("ldn: network info, %u node(s)", out->count); return RES_OK;
}
uint32_t dm_ldn_advertise(const void *data, size_t length) {
    if (length > 384 || (length && !data)) return DM_LDN_BAD_ARGUMENT;
    pthread_mutex_lock(&lan.lock);
    if (lan.state != DM_LDN_HOST && lan.state != DM_LDN_AP) { pthread_mutex_unlock(&lan.lock); return DM_LDN_BAD_STATE; }
    if (length != lan.info.advertise_size || (length && memcmp(lan.info.advertise, data, length))) {
        memset(lan.info.advertise, 0, sizeof lan.info.advertise); if (length) memcpy(lan.info.advertise, data, length);
        lan.info.advertise_size = length; changed_locked();
    }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); return RES_OK;
}

HLE_FORCE("_ZN2nn3ldn10InitializeEv", "initialize local multiplayer transport when DM_LDN is enabled", Result, h_ldn_Init, void) { return dm_ldn_init(); }
HLE_FORCE("_ZN2nn3ldn8FinalizeEv", "close local multiplayer sessions and discovery", void, h_ldn_Fini, void) { dm_ldn_finalize(); }
HLE_FORCE("_ZN2nn3ldn8GetStateEv", "local multiplayer state", int, h_ldn_State, void) { return dm_ldn_state(); }
HLE_FORCE("_ZN2nn3ldn22AttachStateChangeEventEPNS_2os15SystemEventTypeE", "local multiplayer state and membership event", void, h_ldn_Attach, void *ev) {
    hle_bind_system_event(ev, 1); pthread_mutex_lock(&lan.lock); lan.event = hle_system_event_binding(ev); pthread_mutex_unlock(&lan.lock);
}
HLE_FORCE("_ZN2nn3ldn11OpenStationEv", "open a local multiplayer station", Result, h_ldn_OpenSta, void) { return dm_ldn_open(0); }
HLE_FORCE("_ZN2nn3ldn12CloseStationEv", "close a local multiplayer station", Result, h_ldn_CloseSta, void) { return dm_ldn_close(0); }
HLE_FORCE("_ZN2nn3ldn15OpenAccessPointEv", "open a local multiplayer host", Result, h_ldn_OpenAp, void) { return dm_ldn_open(1); }
HLE_FORCE("_ZN2nn3ldn16CloseAccessPointEv", "close a local multiplayer host", Result, h_ldn_CloseAp, void) { return dm_ldn_close(1); }
HLE_FORCE("_ZN2nn3ldn10DisconnectEv", "leave a local multiplayer room", Result, h_ldn_Disc, void) { return dm_ldn_disconnect(0); }
HLE_FORCE("_ZN2nn3ldn14DestroyNetworkEv", "close a local multiplayer room", Result, h_ldn_Destroy, void) { return dm_ldn_disconnect(1); }
HLE_FORCE("_ZN2nn3ldn4ScanEPNS0_11NetworkInfoEPiiRKNS0_10ScanFilterEi", "discover compatible local multiplayer rooms", Result, h_ldn_Scan, dm_ldn_info *o, int *n, int cap, const dm_ldn_filter *f, int ch) { return dm_ldn_scan(o, n, cap, f, ch, 0); }
HLE_FORCE("_ZN2nn3ldn11ScanPrivateEPNS0_11NetworkInfoEPiiRKNS0_10ScanFilterEi", "discover private local multiplayer rooms", Result, h_ldn_ScanP, dm_ldn_info *o, int *n, int cap, const dm_ldn_filter *f, int ch) { return dm_ldn_scan(o, n, cap, f, ch, 1); }
HLE_FORCE("_ZN2nn3ldn13CreateNetworkERKNS0_13NetworkConfigERKNS0_14SecurityConfigERKNS0_10UserConfigE", "create a local multiplayer room", Result, h_ldn_Create, const dm_ldn_config *a, const dm_ldn_security *b, const dm_ldn_user *c) { return dm_ldn_create(a, b, NULL, c, 0, NULL); }
HLE_FORCE("_ZN2nn3ldn20CreateNetworkPrivateERKNS0_13NetworkConfigERKNS0_14SecurityConfigERKNS0_17SecurityParameterERKNS0_10UserConfigEiPKNS0_12AddressEntryE", "create a private local multiplayer room", Result, h_ldn_CreateP, const dm_ldn_config *a, const dm_ldn_security *b, const dm_ldn_secret *c, const dm_ldn_user *d, int n, const dm_ldn_address *e) { return dm_ldn_create(a, b, c, d, n, e); }
HLE_FORCE("_ZN2nn3ldn7ConnectERKNS0_11NetworkInfoERKNS0_14SecurityConfigERKNS0_10UserConfigEiNS0_13ConnectOptionE", "join a local multiplayer room", Result, h_ldn_Connect, const dm_ldn_info *a, const dm_ldn_security *b, const dm_ldn_user *c, int v, int o) { (void)o; return dm_ldn_connect(a, b, c, v); }
static Result connect_private(const dm_ldn_config *a, const dm_ldn_security *b, const dm_ldn_secret *c, const dm_ldn_user *d, int v) {
    if (!a || !c) return DM_LDN_BAD_ARGUMENT;
    dm_ldn_filter filter = {.id.intent = a->intent, .flags = 1 | 2 | 32}; memcpy(filter.id.session, c->session, 16);
    dm_ldn_info info; int count = 0; Result r = dm_ldn_scan(&info, &count, 1, &filter, 0, 1);
    return r ? r : count ? dm_ldn_connect(&info, b, d, v) : DM_LDN_NOT_FOUND;
}
HLE_FORCE("_ZN2nn3ldn14ConnectPrivateERKNS0_13NetworkConfigERKNS0_14SecurityConfigERKNS0_17SecurityParameterERKNS0_10UserConfigEiNS0_13ConnectOptionE", "join a private local multiplayer room", Result, h_ldn_ConnectP, const dm_ldn_config *a, const dm_ldn_security *b, const dm_ldn_secret *c, const dm_ldn_user *d, int v, int o) { (void)o; return connect_private(a, b, c, d, v); }
HLE_FORCE("_ZN2nn3ldn14GetNetworkInfoEPNS0_11NetworkInfoE", "local multiplayer network and nodes", Result, h_ldn_NetInfo, dm_ldn_info *o) { return dm_ldn_info_get(o, NULL, 0); }
HLE_FORCE("_ZN2nn3ldn14GetNetworkInfoEPNS0_11NetworkInfoEPNS0_16NodeLatestUpdateEi", "local multiplayer node change flags", Result, h_ldn_NetUpdate, dm_ldn_info *o, dm_ldn_update *u, int n) { return dm_ldn_info_get(o, u, n); }
HLE_FORCE("_ZN2nn3ldn14GetIpv4AddressEPNS0_11Ipv4AddressEPNS0_10SubnetMaskE", "local multiplayer IPv4 interface (LDN host byte order)", Result, h_ldn_Ip, uint32_t *a, uint32_t *m) {
    if (!a || !m) return DM_LDN_BAD_ARGUMENT; if (!dm_lan_enabled() || !dm_lan_ip()) { *a = *m = 0; return RES_FAIL; }
    *a = ntohl(dm_lan_ip()); *m = ntohl(dm_lan_mask()); return RES_OK;
}
HLE_FORCE("_ZN2nn3ldn20GetSecurityParameterEPNS0_17SecurityParameterE", "local multiplayer session security parameters", Result, h_ldn_SecPrm, dm_ldn_secret *o) {
    if (!o) return DM_LDN_BAD_ARGUMENT; pthread_mutex_lock(&lan.lock); Result r = DM_LDN_BAD_STATE;
    if (lan.state == DM_LDN_HOST || lan.state == DM_LDN_CONNECTED) { memcpy(o->server_random, lan.info.server_random, 16); memcpy(o->session, lan.info.id.session, 16); r = 0; }
    pthread_mutex_unlock(&lan.lock); return r;
}
HLE_FORCE("_ZN2nn3ldn16SetAdvertiseDataEPKvm", "update local room advertisement", Result, h_ldn_Adv, const void *d, uint64_t n) { return dm_ldn_advertise(d, n); }
HLE_FORCE("_ZN2nn3ldn19GetDisconnectReasonEv", "local multiplayer disconnect reason", int, h_ldn_DiscReason, void) { pthread_mutex_lock(&lan.lock); int r = lan.reason; pthread_mutex_unlock(&lan.lock); return r; }
HLE_FORCE("_ZN2nn3ldn20AddAcceptFilterEntryENS0_10MacAddressE", "add a local room admission filter", Result, h_ldn_Filter, uint64_t mac) {
    pthread_mutex_lock(&lan.lock); Result r = DM_LDN_BAD_ARGUMENT;
    if (lan.filter_count < 8) { memcpy(lan.filters[lan.filter_count++].bytes, &mac, 6); r = 0; }
    pthread_mutex_unlock(&lan.lock); return r;
}
HLE_FORCE("_ZN2nn3ldn17ClearAcceptFilterEv", "clear local room admission filters", Result, h_ldn_FilterClear, void) { pthread_mutex_lock(&lan.lock); lan.filter_count = 0; pthread_mutex_unlock(&lan.lock); return 0; }
HLE_FORCE("_ZN2nn3ldn22SetStationAcceptPolicyENS0_12AcceptPolicyE", "set local room admission policy", Result, h_ldn_Policy, int policy) {
    if (policy < 0 || policy > 3) return DM_LDN_BAD_ARGUMENT;
    pthread_mutex_lock(&lan.lock); lan.info.policy = policy; changed_locked(); pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); return RES_OK;
}
HLE_FORCE("_ZN2nn3ldn6RejectENS0_11Ipv4AddressE", "remove a local multiplayer station", Result, h_ldn_Reject, uint32_t ip) {
    int found = 0; pthread_mutex_lock(&lan.lock);
    if (lan.state == DM_LDN_HOST) for (int i = 1; i < 8; i++) if (lan.info.nodes[i].connected && lan.info.nodes[i].ip == ip) {
        lan.info.nodes[i].connected = 0; lan.info.count--; lan.updates[i].change |= 2; changed_locked(); found = 1; break;
    }
    pthread_mutex_unlock(&lan.lock); wake_worker(); signal_change(); return found ? RES_OK : DM_LDN_BAD_ARGUMENT;
}
HLE_FORCE("_ZN2nn3ldn16GetNetworkConfigEPNS0_13NetworkConfigE", "local room configuration", Result, h_ldn_NetCfg, dm_ldn_config *o) {
    if (!o) return DM_LDN_BAD_ARGUMENT; pthread_mutex_lock(&lan.lock); Result r = DM_LDN_BAD_STATE;
    if (lan.state == DM_LDN_HOST || lan.state == DM_LDN_CONNECTED) {
        memset(o, 0, sizeof *o); o->intent = lan.info.id.intent; o->channel = lan.info.common.channel; o->capacity = lan.info.capacity; o->version = lan.info.nodes[0].version; r = 0;
    }
    pthread_mutex_unlock(&lan.lock); return r;
}
