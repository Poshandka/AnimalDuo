#include "hle.h"
#include "hle_lan.h"
#include "hle_socket.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

// bsd:u uses O_NONBLOCK=0x800 (libnx source/runtime/devices/socket.c),
// independently of Darwin's O_NONBLOCK. The IPv4 sockaddr and poll layouts are BSD.
enum { SK_MAX = 1024, SK_NONBLOCK = 0x800, SK_ENETDOWN = 100 };
typedef struct { int used, fd, type, flags; uint64_t generation; } sk_slot;
typedef struct { int fd, slot, type, flags; uint64_t generation; } sk_ref;
static sk_slot sockets[SK_MAX];
static pthread_mutex_t sk_lock = PTHREAD_MUTEX_INITIALIZER;
__thread int dm_sk_errno = SK_ENETDOWN;
// The SDK exposes POSIX/newlib errno numbers, not the BSD service's raw errno.
// In ACNH 3.0.3, main+0x1267e0 classifies 4/11 as a retryable receive;
// Darwin's EAGAIN=35 instead takes the fatal connection-error path.
static int sk_guest_errno(int e) {
    switch (e) {
    case EDEADLK: return 35;
    case EAGAIN: return 11;
    case EINPROGRESS: return 115;
    case EALREADY: return 114;
    case ENOTSOCK: return 88;
    case EDESTADDRREQ: return 89;
    case EMSGSIZE: return 90;
    case EPROTOTYPE: return 91;
    case ENOPROTOOPT: return 92;
    case EPROTONOSUPPORT: return 93;
    case ESOCKTNOSUPPORT: return 94;
    case ENOTSUP: case EOPNOTSUPP: return 95;
    case EPFNOSUPPORT: return 96;
    case EAFNOSUPPORT: return 97;
    case EADDRINUSE: return 98;
    case EADDRNOTAVAIL: return 99;
    case ENETDOWN: return 100;
    case ENETUNREACH: return 101;
    case ENETRESET: return 102;
    case ECONNABORTED: return 103;
    case ECONNRESET: return 104;
    case ENOBUFS: return 105;
    case EISCONN: return 106;
    case ENOTCONN: return 107;
    case ESHUTDOWN: return 108;
    case ETOOMANYREFS: return 109;
    case ETIMEDOUT: return 110;
    case ECONNREFUSED: return 111;
    case EHOSTDOWN: return 112;
    case EHOSTUNREACH: return 113;
    case ELOOP: return 40;
    case ENAMETOOLONG: return 36;
    case ENOTEMPTY: return 39;
    case ENOLCK: return 37;
    case ENOSYS: return 38;
    case EOVERFLOW: return 75;
    case ECANCELED: return 125;
    case EPROTO: return 71;
    default: return e >= 0 && e <= 34 ? e : 5;
    }
}
static int sk_error(int e) { dm_sk_errno = sk_guest_errno(e); return -1; }
static int sk_down(void) { return sk_error(ENETDOWN); }
static uint64_t sk_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000ull + t.tv_nsec / 1000000; }
static void sk_setup(int fd) { int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes); fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); }
static int sk_insert(int fd, int type, int flags) {
    pthread_mutex_lock(&sk_lock);
    for (int i = 0; i < SK_MAX; i++) if (!sockets[i].used) {
        uint64_t generation = sockets[i].generation + 1;
        sockets[i] = (sk_slot){1, fd, type, flags, generation}; pthread_mutex_unlock(&sk_lock); return i;
    }
    pthread_mutex_unlock(&sk_lock); close(fd); return sk_error(EMFILE);
}
static sk_ref sk_get(int fd) {
    dm_lan_wait_guest();
    sk_ref r = {.fd = -1};
    if (!dm_lan_enabled()) { sk_down(); return r; }
    pthread_mutex_lock(&sk_lock);
    if (fd >= 0 && fd < SK_MAX && sockets[fd].used) {
        sk_slot s = sockets[fd]; r = (sk_ref){dup(s.fd), fd, s.type, s.flags, s.generation};
        if (r.fd < 0) sk_error(errno);
    } else sk_error(EBADF);
    pthread_mutex_unlock(&sk_lock); return r;
}
static int sk_live(sk_ref r) {
    pthread_mutex_lock(&sk_lock); int live = sockets[r.slot].used && sockets[r.slot].generation == r.generation;
    pthread_mutex_unlock(&sk_lock); return live;
}
static uint64_t sk_deadline(int fd, int sending) {
    struct timeval t = {0}; socklen_t n = sizeof t;
    if (!getsockopt(fd, SOL_SOCKET, sending ? SO_SNDTIMEO : SO_RCVTIMEO, &t, &n) && (t.tv_sec || t.tv_usec))
        return sk_ms() + (uint64_t)t.tv_sec * 1000 + (t.tv_usec + 999) / 1000;
    return UINT64_MAX;
}
static int sk_wait(sk_ref r, short events, uint64_t deadline) {
    for (;;) {
        if (!sk_live(r)) return sk_error(EBADF);
        uint64_t now = sk_ms(); if (now >= deadline) return sk_error(EWOULDBLOCK);
        int ms = deadline == UINT64_MAX || deadline - now > 100 ? 100 : (int)(deadline - now);
        struct pollfd p = {r.fd, events, 0};
        dm_thread_native_wait(1); int n = poll(&p, 1, ms); int e = errno; dm_thread_native_wait(0);
        if (n > 0) return 0; if (n < 0 && e != EINTR) return sk_error(e);
    }
}
static int sk_address(const void *in, unsigned n, struct sockaddr_in *out) {
    if (!in || n < sizeof *out) return sk_error(EINVAL);
    memcpy(out, in, sizeof *out);
    if (out->sin_family != AF_INET) return sk_error(EAFNOSUPPORT);
    out->sin_len = sizeof *out; return 0;
}
static int sk_copy_address(void *out, unsigned *size, const struct sockaddr_in *in) {
    if (!out) return 0; if (!size) return sk_error(EFAULT);
    unsigned n = *size < sizeof *in ? *size : sizeof *in; memcpy(out, in, n); *size = sizeof *in; return 0;
}
static int sk_result(sk_ref r, int result) { int e = errno; close(r.fd); dm_lan_wait_guest(); return result < 0 ? sk_error(e) : result; }
static int sk_autobind(sk_ref r) {
    struct sockaddr_in own = {0}; socklen_t n = sizeof own;
    if (getsockname(r.fd, (void *)&own, &n)) return -1;
    if (own.sin_port) return 0;
    own.sin_len = sizeof own; own.sin_family = AF_INET; own.sin_addr.s_addr = dm_lan_ip();
    if (!own.sin_addr.s_addr) { errno = EADDRNOTAVAIL; return -1; }
    return bind(r.fd, (void *)&own, sizeof own);
}
static void sk_record(int sending, size_t bytes) {
    if (!getenv("DM_NET_LOG")) return;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER; static uint64_t tx, rx, tx_bytes, rx_bytes, last;
    pthread_mutex_lock(&lock);
    if (sending) { tx++; tx_bytes += bytes; } else { rx++; rx_bytes += bytes; }
    uint64_t now = sk_ms();
    if (now - last >= 1000) { LOG("lan sockets: sent %llu / %llu bytes, received %llu / %llu bytes", tx, tx_bytes, rx, rx_bytes); tx = rx = tx_bytes = rx_bytes = 0; last = now; }
    pthread_mutex_unlock(&lock);
}
int dm_sk_socket(int family, int type, int protocol) {
    if (!dm_lan_enabled()) return sk_down();
    if (family != AF_INET) return sk_error(EAFNOSUPPORT);
    if (type != SOCK_DGRAM && type != SOCK_STREAM) return sk_error(EPROTONOSUPPORT);
    if (protocol && protocol != (type == SOCK_DGRAM ? IPPROTO_UDP : IPPROTO_TCP)) return sk_error(EPROTONOSUPPORT);
    int fd = socket(AF_INET, type, protocol); if (fd < 0) return sk_error(errno); sk_setup(fd);
    int guest = sk_insert(fd, type, 0); if (getenv("DM_NET_LOG")) LOG("lan socket: created %d type %d", guest, type); return guest;
}
int dm_sk_close(int fd) {
    if (!dm_lan_enabled()) return sk_down();
    pthread_mutex_lock(&sk_lock);
    if (fd < 0 || fd >= SK_MAX || !sockets[fd].used) { pthread_mutex_unlock(&sk_lock); return sk_error(EBADF); }
    int native = sockets[fd].fd; sockets[fd].used = 0; sockets[fd].generation++;
    pthread_mutex_unlock(&sk_lock); close(native); return 0;
}
void dm_sk_finalize(void) {
    pthread_mutex_lock(&sk_lock);
    for (int i = 0; i < SK_MAX; i++) if (sockets[i].used) { close(sockets[i].fd); sockets[i].used = 0; sockets[i].generation++; }
    pthread_mutex_unlock(&sk_lock);
}
int dm_sk_bind(int fd, const void *address, unsigned length) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1; struct sockaddr_in a;
    if (sk_address(address, length, &a)) { close(r.fd); return -1; }
    uint32_t ip = dm_lan_ip();
    if (!ip || (a.sin_addr.s_addr && a.sin_addr.s_addr != ip)) { close(r.fd); return sk_error(EADDRNOTAVAIL); }
    a.sin_addr.s_addr = ip;
    int result = bind(r.fd, (void *)&a, sizeof a), error = errno;
    if (getenv("DM_NET_LOG")) LOG("lan socket: bind %d port %u -> %d", fd, ntohs(a.sin_port), result);
    errno = error; return sk_result(r, result);
}
int dm_sk_connect(int fd, const void *address, unsigned length) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1; struct sockaddr_in a;
    if (sk_address(address, length, &a)) { close(r.fd); return -1; }
    if (!dm_lan_peer(a.sin_addr.s_addr)) { close(r.fd); return sk_error(ENETUNREACH); }
    // A socket bound to INADDR_ANY on Horizon belongs to LDN's interface, not all host interfaces.
    if (sk_autobind(r)) return sk_result(r, -1);
    int result = connect(r.fd, (void *)&a, sizeof a), e = errno;
    if (result < 0 && e == EINPROGRESS && !(r.flags & SK_NONBLOCK)) {
        if (sk_wait(r, POLLOUT, sk_deadline(r.fd, 1))) { close(r.fd); return -1; }
        socklen_t n = sizeof e; if (getsockopt(r.fd, SOL_SOCKET, SO_ERROR, &e, &n)) e = errno;
        result = e ? -1 : 0;
    }
    close(r.fd);
    if (getenv("DM_NET_LOG")) LOG("lan socket: connect %d port %u -> %d (%d)", fd, ntohs(a.sin_port), result, result < 0 ? e : 0);
    return result < 0 ? sk_error(e) : result;
}
int dm_sk_listen(int fd, int backlog) { sk_ref r = sk_get(fd); return r.fd < 0 ? -1 : sk_result(r, listen(r.fd, backlog)); }
int dm_sk_accept(int fd, void *address, unsigned *length) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1;
    uint64_t deadline = sk_deadline(r.fd, 0);
    for (;;) {
        struct sockaddr_in a = {0}; socklen_t n = sizeof a; int accepted = accept(r.fd, (void *)&a, &n);
        if (accepted >= 0) {
            if (!dm_lan_peer(a.sin_addr.s_addr)) { close(accepted); continue; }
            if (sk_copy_address(address, length, &a)) { close(accepted); close(r.fd); return -1; }
            sk_setup(accepted); close(r.fd); return sk_insert(accepted, SOCK_STREAM, 0);
        }
        if (errno == EINTR) continue;
        if ((errno == EAGAIN || errno == EWOULDBLOCK) && !(r.flags & SK_NONBLOCK)) {
            if (!sk_wait(r, POLLIN, deadline)) continue; close(r.fd); return -1;
        }
        return sk_result(r, -1);
    }
}
int dm_sk_name(int fd, void *address, unsigned *length, int peer) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1; struct sockaddr_in a = {0}; socklen_t n = sizeof a;
    int result = peer ? getpeername(r.fd, (void *)&a, &n) : getsockname(r.fd, (void *)&a, &n);
    if (result >= 0 && sk_copy_address(address, length, &a)) { close(r.fd); return -1; }
    return sk_result(r, result);
}
int dm_sk_option(int fd, int level, int option, void *value, unsigned *length, int set) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1;
    if (!value || !length) { close(r.fd); return sk_error(EFAULT); }
    int result;
    if (level == SOL_SOCKET && (option == SO_RCVTIMEO || option == SO_SNDTIMEO)) {
        if (*length < 16) { close(r.fd); return sk_error(EINVAL); }
        int64_t guest[2]; struct timeval t = {0}; socklen_t n = sizeof t;
        if (set) {
            memcpy(guest, value, 16);
            if (guest[0] < 0 || guest[1] < 0 || guest[1] >= 1000000) { close(r.fd); return sk_error(EINVAL); }
            t.tv_sec = guest[0]; t.tv_usec = guest[1]; result = setsockopt(r.fd, level, option, &t, sizeof t);
        } else {
            result = getsockopt(r.fd, level, option, &t, &n); guest[0] = t.tv_sec; guest[1] = t.tv_usec;
            if (result >= 0) { memcpy(value, guest, 16); *length = 16; }
        }
    } else {
        socklen_t n = *length;
        result = set ? setsockopt(r.fd, level, option, value, n) : getsockopt(r.fd, level, option, value, &n);
        if (!set && result >= 0) *length = n;
    }
    int error = errno;
    if (!set && result >= 0 && level == SOL_SOCKET && option == SO_ERROR && *length >= sizeof(int)) {
        int pending; memcpy(&pending, value, sizeof pending); pending = sk_guest_errno(pending); memcpy(value, &pending, sizeof pending);
    }
    if (getenv("DM_NET_LOG") && set) LOG("lan socket: set option %d level %#x option %#x -> %d", fd, level, option, result);
    errno = error; return sk_result(r, result);
}
int dm_sk_fcntl(int fd, int command, int flags) {
    if (!dm_lan_enabled()) return sk_down();
    pthread_mutex_lock(&sk_lock);
    if (fd < 0 || fd >= SK_MAX || !sockets[fd].used) { pthread_mutex_unlock(&sk_lock); return sk_error(EBADF); }
    int result = 0;
    if (command == 3) result = sockets[fd].flags;
    else if (command == 4 && !(flags & ~SK_NONBLOCK)) sockets[fd].flags = flags;
    else result = -1;
    pthread_mutex_unlock(&sk_lock);
    if (getenv("DM_NET_LOG")) LOG("lan socket: fcntl %d command %d flags %#x -> %d", fd, command, flags, result);
    return result < 0 ? sk_error(EINVAL) : result;
}
int dm_sk_shutdown(int fd, int how) { sk_ref r = sk_get(fd); return r.fd < 0 ? -1 : sk_result(r, shutdown(r.fd, how)); }
long dm_sk_send(int fd, const void *buffer, uint64_t length, int flags, const void *address, unsigned address_length) {
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1;
    if ((!buffer && length) || length > SSIZE_MAX) { close(r.fd); return sk_error(EINVAL); }
    struct sockaddr_in a = {0}; socklen_t n = sizeof a;
    if (address) { if (sk_address(address, address_length, &a)) { close(r.fd); return -1; } }
    else if (getpeername(r.fd, (void *)&a, &n)) return sk_result(r, -1);
    uint32_t destinations[8]; int count;
    if (address && dm_lan_broadcast(a.sin_addr.s_addr) && r.type == SOCK_DGRAM) {
        int allowed = 0; socklen_t size = sizeof allowed;
        if (getsockopt(r.fd, SOL_SOCKET, SO_BROADCAST, &allowed, &size)) return sk_result(r, -1);
        if (!allowed) { close(r.fd); return sk_error(EACCES); }
        count = dm_lan_peers(destinations, 8);
    }
    else { if (!dm_lan_peer(a.sin_addr.s_addr)) { close(r.fd); return sk_error(ENETUNREACH); } destinations[0] = a.sin_addr.s_addr; count = 1; }
    if (sk_autobind(r)) return sk_result(r, -1);
    // SO_NOSIGPIPE supplies Horizon's MSG_NOSIGNAL behavior without passing its different flag value to Darwin.
    int native_flags = flags & ~0x20000; uint64_t deadline = sk_deadline(r.fd, 1); ssize_t result = length;
    for (int i = 0; i < count; i++) {
        a.sin_addr.s_addr = destinations[i];
        for (;;) {
            result = address ? sendto(r.fd, buffer, length, native_flags, (void *)&a, sizeof a) : send(r.fd, buffer, length, native_flags);
            if (result >= 0) { sk_record(1, result); break; }
            if (errno == EINTR) continue;
            if ((errno == EAGAIN || errno == EWOULDBLOCK) && !(r.flags & SK_NONBLOCK) && !(flags & MSG_DONTWAIT)) {
                if (!sk_wait(r, POLLOUT, deadline)) continue; close(r.fd); return -1;
            }
            return sk_result(r, -1);
        }
    }
    close(r.fd); dm_lan_wait_guest(); return result;
}
long dm_sk_recv(int fd, void *buffer, uint64_t length, int flags, void *address, unsigned *address_length) {
    if (getenv("DM_NET_TRACE")) LOG("lan socket: recv %d flags %#x length %llu address length %u", fd, flags, length, address_length ? *address_length : 0);
    sk_ref r = sk_get(fd); if (r.fd < 0) return -1;
    if ((!buffer && length) || length > SSIZE_MAX || (address && !address_length)) { close(r.fd); return sk_error(EINVAL); }
    uint64_t deadline = sk_deadline(r.fd, 0);
    for (;;) {
        if (!sk_live(r)) { close(r.fd); return sk_error(EBADF); }
        struct sockaddr_in a = {0}; socklen_t n = sizeof a;
        ssize_t result = recvfrom(r.fd, buffer, length, flags & ~0x20000, (void *)&a, &n);
        if (result >= 0) {
            if (r.type == SOCK_DGRAM && !dm_lan_peer(a.sin_addr.s_addr)) {
                // A peek must also remove a rejected datagram, otherwise the same
                // non-member packet would remain at the head of the receive queue.
                if (flags & MSG_PEEK) recvfrom(r.fd, buffer, length, (flags & ~(MSG_PEEK | 0x20000)) | MSG_DONTWAIT, NULL, NULL);
                continue;
            }
            if (sk_copy_address(address, address_length, &a)) { close(r.fd); return -1; }
            sk_record(0, result); close(r.fd); dm_lan_wait_guest(); return result;
        }
        if (errno == EINTR) continue;
        if ((errno == EAGAIN || errno == EWOULDBLOCK) && !(r.flags & SK_NONBLOCK) && !(flags & MSG_DONTWAIT)) {
            if (!sk_wait(r, POLLIN, deadline)) continue; close(r.fd); return -1;
        }
        int error = errno;
        if (getenv("DM_NET_TRACE")) LOG("lan socket: recv %d failed with native errno %d (SDK %d)", fd, error, sk_guest_errno(error));
        errno = error;
        return sk_result(r, -1);
    }
}
typedef struct { int32_t fd; int16_t events, revents; } sk_pollfd;
void dm_guest_sleep_ns(int64_t);
static int sk_idle(int64_t ms) { dm_guest_sleep_ns((ms < 0 ? 100 : ms) * 1000000); return 0; }
int dm_sk_poll(void *fds, uint64_t count, int ms) {
    if (count > SK_MAX || (count && !fds)) return sk_error(EINVAL);
    sk_pollfd *guest = fds;
    if (!dm_lan_enabled()) {
        for (uint64_t i = 0; i < count; i++) if (guest[i].fd >= 0) return sk_down();
        for (uint64_t i = 0; i < count; i++) guest[i].revents = 0;
        return sk_idle(ms);
    }
    // Guest network threads can have 8 KB stacks; the poll vectors live on the heap.
    struct pollfd *native = calloc(count, sizeof *native); sk_ref *refs = calloc(count, sizeof *refs);
    if (count && (!native || !refs)) { free(native); free(refs); return sk_error(ENOMEM); }
    int real = 0, invalid = 0;
    for (uint64_t i = 0; i < count; i++) {
        guest[i].revents = 0; refs[i] = (sk_ref){.fd = -1}; native[i] = (struct pollfd){-1, guest[i].events, 0};
        if (guest[i].fd >= 0) {
            refs[i] = sk_get(guest[i].fd); native[i].fd = refs[i].fd;
            if (refs[i].fd < 0) { guest[i].revents = POLLNVAL; invalid++; } else real++;
        }
    }
    if (!real && !invalid) { free(native); free(refs); return sk_idle(ms); }
    uint64_t deadline = ms < 0 ? UINT64_MAX : sk_ms() + ms; int result = -1, e = 0;
    for (;;) {
        uint64_t now = sk_ms();
        uint64_t remaining = deadline > now ? deadline - now : 0;
        int timeout = invalid ? 0 : remaining > 100 ? 100 : (int)remaining;
        dm_thread_native_wait(1); int n = poll(native, count, timeout); e = errno; dm_thread_native_wait(0);
        result = 0;
        for (uint64_t i = 0; i < count; i++) {
            if (refs[i].fd >= 0) guest[i].revents = sk_live(refs[i]) ? native[i].revents : POLLNVAL;
            if (guest[i].revents) result++;
        }
        if (n < 0 && e != EINTR) { result = -1; break; }
        if (result || ms == 0 || sk_ms() >= deadline) break;
    }
    for (uint64_t i = 0; i < count; i++) if (refs[i].fd >= 0) close(refs[i].fd);
    free(native); free(refs); dm_lan_wait_guest(); return result < 0 ? sk_error(e) : result;
}
int dm_sk_select(int nfds, uint64_t *read_set, uint64_t *write_set, uint64_t *except_set, const int64_t *tv) {
    if (nfds < 0 || nfds > SK_MAX || (tv && (tv[0] < 0 || tv[1] < 0 || tv[1] >= 1000000))) return sk_error(EINVAL);
    sk_pollfd *fds = calloc(nfds ? nfds : 1, sizeof *fds); if (!fds) return sk_error(ENOMEM);
    int count = 0; uint64_t *sets[3] = {read_set, write_set, except_set};
    for (int i = 0; i < nfds; i++) {
        short events = 0;
        for (int k = 0; k < 3; k++) if (sets[k] && (sets[k][i / 64] >> (i % 64) & 1)) events |= k == 0 ? POLLIN : k == 1 ? POLLOUT : POLLPRI;
        if (events) fds[count++] = (sk_pollfd){i, events, 0};
    }
    int64_t ms64 = tv ? tv[0] > INT_MAX / 1000 ? INT_MAX : tv[0] * 1000 + (tv[1] + 999) / 1000 : -1;
    int result = dm_sk_poll(fds, count, ms64 > INT_MAX ? INT_MAX : (int)ms64); if (result < 0) { free(fds); return result; }
    size_t bytes = ((size_t)nfds + 63) / 64 * 8;
    for (int k = 0; k < 3; k++) if (sets[k]) memset(sets[k], 0, bytes);
    result = 0;
    for (int i = 0; i < count; i++) {
        int fd = fds[i].fd; short events = fds[i].revents;
        if (events & POLLNVAL) { free(fds); return sk_error(EBADF); }
        if (read_set && (fds[i].events & POLLIN) && (events & (POLLIN | POLLHUP | POLLERR))) { read_set[fd / 64] |= 1ull << (fd % 64); result++; }
        if (write_set && (fds[i].events & POLLOUT) && (events & (POLLOUT | POLLERR))) { write_set[fd / 64] |= 1ull << (fd % 64); result++; }
        if (except_set && (fds[i].events & POLLPRI) && (events & POLLPRI)) { except_set[fd / 64] |= 1ull << (fd % 64); result++; }
    }
    free(fds); return result;
}
