// Exercise the SDK socket ABI, blocking boundaries and descriptor ownership.
#include "../hle_socket.c"
#include "../hle_net.c"
#include <assert.h>
#include <stdatomic.h>
static int enabled = 1;
static _Atomic int waiting;
static _Atomic int freeze_on_native_wait;
static pthread_mutex_t clock_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t clock_changed = PTHREAD_COND_INITIALIZER;
static uint64_t clock_lag, clock_frozen;
static int clock_held;
uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000000ull + t.tv_nsec; }
uint64_t guest_ns(void) {
    pthread_mutex_lock(&clock_lock);
    uint64_t n = clock_held ? clock_frozen : now_ns() - clock_lag;
    pthread_mutex_unlock(&clock_lock); return n;
}
static void hold_clock(int on) {
    pthread_mutex_lock(&clock_lock);
    if (on && !clock_held) clock_frozen = now_ns() - clock_lag;
    if (!on && clock_held) clock_lag = now_ns() - clock_frozen;
    clock_held = on; pthread_cond_broadcast(&clock_changed);
    pthread_mutex_unlock(&clock_lock);
}
int dm_lan_enabled(void) { return enabled; }
void dm_lan_wait_guest(void) {
    pthread_mutex_lock(&clock_lock);
    while (clock_held) pthread_cond_wait(&clock_changed, &clock_lock);
    pthread_mutex_unlock(&clock_lock);
}
uint32_t dm_lan_ip(void) { return htonl(INADDR_LOOPBACK); }
uint32_t dm_lan_mask(void) { return htonl(0xff000000); }
int dm_lan_peer(uint32_t ip) { return ip == dm_lan_ip(); }
int dm_lan_peers(uint32_t *ips, int n) { if (n) ips[0] = dm_lan_ip(); return !!n; }
int dm_lan_broadcast(uint32_t ip) { return ip == INADDR_BROADCAST; }
void dm_thread_native_wait(int on) {
    if (on) {
        // Freeze at the worker's first native wait, after its deadline exists.
        // A busy test runner cannot consume the timeout before the test pauses it.
        if (atomic_exchange(&freeze_on_native_wait, 0)) hold_clock(1);
        waiting++;
    } else waiting--;
}
void dm_guest_sleep_ns(int64_t ns) { struct timespec t = {ns / 1000000000, ns % 1000000000}; nanosleep(&t, NULL); }
static struct sockaddr_in local(unsigned port) {
    return (struct sockaddr_in){.sin_len = 16, .sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = dm_lan_ip()};
}
static void *wait_receive(void *arg) {
    int fd = *(int *)arg; char data;
    assert(dm_sk_recv(fd, &data, 1, 0, NULL, NULL) == -1 && dm_sk_errno == EBADF);
    return NULL;
}
static void *thread_errno(void *unused) {
    (void)unused; assert(dm_sk_close(999) == -1 && dm_sk_errno == EBADF); return NULL;
}
typedef struct { int fd, poll, result, error; char value; _Atomic int done; } paused_read;
static void *read_across_pause(void *arg) {
    paused_read *r = arg;
    if (r->poll) {
        sk_pollfd f = {r->fd, POLLIN, 0};
        r->result = dm_sk_poll(&f, 1, 150);
        if (r->result == 1) assert(f.revents & POLLIN);
    } else r->result = (int)dm_sk_recv(r->fd, &r->value, 1, 0, NULL, NULL);
    r->error = dm_sk_errno; atomic_store(&r->done, 1); return NULL;
}
static void paused_deadline_tests(int fd, struct sockaddr_in a) {
    int64_t timeout[2] = {0, 150000}; unsigned size = sizeof timeout;
    assert(!dm_sk_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout, &size, 1));
    for (int poll = 0; poll < 2; poll++) {
        paused_read result = {.fd = fd, .poll = poll}; pthread_t thread;
        atomic_store(&freeze_on_native_wait, 1);
        assert(!pthread_create(&thread, NULL, read_across_pause, &result));
        for (int i = 0; i < 1000 && !waiting; i++) usleep(1000);
        assert(waiting && !atomic_load(&freeze_on_native_wait));
        // Exceed the entire active timeout while the peer's guest is paused.
        usleep(300000); assert(!atomic_load(&result.done));
        assert(sendto(sockets[fd].fd, "p", 1, 0, (void *)&a, sizeof a) == 1);
        hold_clock(0); pthread_join(thread, NULL);
        assert(result.result == 1 && (poll || result.value == 'p'));
        if (poll) { char value; assert(dm_sk_recv(fd, &value, 1, 0, NULL, NULL) == 1 && value == 'p'); }
        assert(!waiting);
    }
    puts("BSD sockets: in-flight receive and poll retain active deadlines across a guest pause PASS");
}
int main(void) {
    enabled = 0; assert(dm_sk_socket(AF_INET, SOCK_DGRAM, 0) == -1 && dm_sk_errno == 100);
    sk_pollfd ignored = {-1, POLLIN, 17}; assert(!dm_sk_poll(&ignored, 1, 0) && !ignored.revents);
    dm_nifm_set_local(1); assert(!dm_nifm_local_available()); enabled = 1;
    dm_nifm_set_local(0); assert(!h_nifm_Available()); dm_nifm_set_local(1);
    h_nifm_Submit(); assert(h_nifm_OnHold() && !h_nifm_Available());
    dm_guest_sleep_ns(60000000); assert(!h_nifm_OnHold() && h_nifm_Available());
    uint32_t ip, mask, gateway, dns1, dns2;
    assert(!dm_nifm_ip_config(&ip, &mask, &gateway, &dns1, &dns2));
    assert(ip == dm_lan_ip() && mask == dm_lan_mask() && !gateway && !dns1 && !dns2);
    int fd = dm_sk_socket(AF_INET, SOCK_DGRAM, 0); assert(fd >= 0);
    struct sockaddr_in a = local(0); a.sin_addr.s_addr = INADDR_ANY;
    assert(!dm_sk_bind(fd, &a, sizeof a)); unsigned size = sizeof a;
    assert(!dm_sk_name(fd, &a, &size, 0) && size == 16 && a.sin_addr.s_addr == ip && a.sin_port);
    assert(dm_sk_fcntl(fd, 3, 0) == 0 && !dm_sk_fcntl(fd, 4, 0x800) && dm_sk_fcntl(fd, 3, 0) == 0x800);
    char buf[64]; assert(dm_sk_recv(fd, buf, sizeof buf, 0, NULL, NULL) == -1 && h_sk_GetLastError() == 11);
    assert(dm_sk_recv(fd, buf, sizeof buf, MSG_DONTWAIT, NULL, NULL) == -1 && h_sk_GetLastError() == 11);
    int occupied = dm_sk_socket(AF_INET, SOCK_DGRAM, 0);
    assert(dm_sk_bind(occupied, &a, sizeof a) == -1 && h_sk_GetLastError() == 98);
    assert(!dm_sk_close(occupied));
    pthread_t thread; dm_sk_errno = EACCES; assert(!pthread_create(&thread, NULL, thread_errno, NULL));
    pthread_join(thread, NULL); assert(dm_sk_errno == EACCES);
    assert(dm_sk_send(fd, "hello", 6, 0, &a, sizeof a) == 6);
    sk_pollfd pollfd = {fd, POLLIN, 0}; assert(dm_sk_poll(&pollfd, 1, 500) == 1 && (pollfd.revents & POLLIN));
    struct sockaddr_in source; size = sizeof source;
    assert(dm_sk_recv(fd, buf, sizeof buf, MSG_PEEK, &source, &size) == 6 && !strcmp(buf, "hello"));
    uint64_t read_set[16] = {0}; read_set[fd / 64] |= 1ull << (fd % 64); int64_t zero[2] = {0};
    assert(dm_sk_select(fd + 1, read_set, NULL, NULL, zero) == 1 && (read_set[fd / 64] >> (fd % 64) & 1));
    assert(dm_sk_recv(fd, buf, sizeof buf, 0, NULL, NULL) == 6);
    a.sin_addr.s_addr = INADDR_BROADCAST;
    assert(dm_sk_send(fd, "broadcast", 10, 0, &a, sizeof a) == -1 && dm_sk_errno == EACCES);
    int yes = 1; size = sizeof yes; assert(!dm_sk_option(fd, SOL_SOCKET, SO_BROADCAST, &yes, &size, 1));
    assert(dm_sk_send(fd, "broadcast", 10, 0, &a, sizeof a) == 10);
    assert(dm_sk_poll(&pollfd, 1, 500) == 1 && (pollfd.revents & POLLIN));
    assert(dm_sk_recv(fd, buf, sizeof buf, 0, NULL, NULL) == 10 && !strcmp(buf, "broadcast"));
    a.sin_addr.s_addr = htonl(0x08080808);
    assert(dm_sk_send(fd, "outside", 8, 0, &a, sizeof a) == -1 && dm_sk_errno == 101);
    int64_t timeout[2] = {0, 25000}; size = sizeof timeout;
    assert(!dm_sk_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout, &size, 1));
    memset(timeout, 0, sizeof timeout); assert(!dm_sk_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout, &size, 0) && timeout[1] == 25000);
    assert(!dm_sk_fcntl(fd, 4, 0)); uint64_t start = sk_ms();
    assert(dm_sk_recv(fd, buf, sizeof buf, 0, NULL, NULL) == -1 && dm_sk_errno == 11 && sk_ms() - start >= 20);
    paused_deadline_tests(fd, a = local(ntohs(source.sin_port)));
    timeout[1] = 0; assert(!dm_sk_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout, &size, 1));
    assert(!pthread_create(&thread, NULL, wait_receive, &fd));
    for (int i = 0; i < 100 && !waiting; i++) usleep(1000); assert(waiting);
    assert(!dm_sk_close(fd)); int replacement = dm_sk_socket(AF_INET, SOCK_DGRAM, 0); assert(replacement == fd);
    pthread_join(thread, NULL); assert(!waiting); assert(!dm_sk_close(replacement));
    pollfd = (sk_pollfd){fd, POLLIN, 0}; assert(dm_sk_poll(&pollfd, 1, 5000) == 1 && pollfd.revents == POLLNVAL);
    int listener = dm_sk_socket(AF_INET, SOCK_STREAM, 0); a = local(0); assert(!dm_sk_bind(listener, &a, 16));
    size = 16; assert(!dm_sk_name(listener, &a, &size, 0) && !dm_sk_listen(listener, 2));
    int client = dm_sk_socket(AF_INET, SOCK_STREAM, 0); assert(!dm_sk_connect(client, &a, 16));
    size = 16; int accepted = dm_sk_accept(listener, &source, &size); assert(accepted >= 0 && source.sin_addr.s_addr == ip);
    assert(dm_sk_send(client, "stream", 7, 0, NULL, 0) == 7 && dm_sk_recv(accepted, buf, 7, MSG_WAITALL, NULL, NULL) == 7 && !strcmp(buf, "stream"));
    assert(!dm_sk_shutdown(client, SHUT_WR) && dm_sk_recv(accepted, buf, 7, 0, NULL, NULL) == 0);
    dm_sk_finalize(); assert(dm_sk_close(listener) == -1 && dm_sk_errno == EBADF);
    puts("BSD sockets: UDP, broadcast, TCP, blocking, errno, NIFM and descriptor lifecycle PASS");
    return 0;
}
