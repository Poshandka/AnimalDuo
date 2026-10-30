// LDN state, admission and real two-process Bonjour/TCP control-plane checks.
#include "../hle_ldn.c"
#include "../hle_socket.c"
#include <assert.h>
__thread _Atomic int dm_host_work;
static _Atomic unsigned signals;
void dm_thread_native_wait(int entering) { (void)entering; }
void dm_guest_sleep_ns(int64_t ns) { struct timespec t = {ns / 1000000000, ns % 1000000000}; nanosleep(&t, NULL); }
void hle_bind_system_event(void *ev, int autoclear) { (void)ev; assert(autoclear); }
uint64_t hle_system_event_binding(void *ev) { return ev ? 1 : 0; }
int hle_signal_system_event_binding(uint64_t id) { if (id) signals++; return !!id; }
static dm_ldn_config config = {.intent.communication_id = 0x01006f8002326000, .intent.scene = 0x1337, .capacity = 2, .version = 7};
static dm_ldn_security security = {.size = 16, .passphrase = "local-test-key-1"};
static dm_ldn_user user = {.name = "LAN test"};
static void pause_ms(int n) { usleep(n * 1000); }
static int data_socket(int type, uint16_t port) {
    int fd = dm_sk_socket(AF_INET, type, 0); assert(fd >= 0);
    struct sockaddr_in a = {.sin_len = 16, .sin_family = AF_INET, .sin_port = htons(port)};
    assert(!dm_sk_bind(fd, &a, 16));
    int64_t timeout[2] = {5, 0}; unsigned n = sizeof timeout;
    assert(!dm_sk_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout, &n, 1)); return fd;
}
static void host_data(int udp, int tcp) {
    char buffer[64]; struct sockaddr_in source; unsigned size = sizeof source;
    assert(dm_sk_recv(udp, buffer, sizeof buffer, 0, &source, &size) == 14 && !strcmp(buffer, "game datagram"));
    assert(dm_sk_send(udp, buffer, 14, 0, &source, size) == 14);
    size = sizeof source; int stream = dm_sk_accept(tcp, &source, &size); assert(stream >= 0);
    assert(dm_sk_recv(stream, buffer, 12, MSG_WAITALL, NULL, NULL) == 12 && !strcmp(buffer, "game stream"));
    assert(dm_sk_send(stream, buffer, 12, 0, NULL, 0) == 12); assert(!dm_sk_close(stream));
}
static void client_data(uint32_t host_ip) {
    int udp = data_socket(SOCK_DGRAM, 0); struct sockaddr_in a = {.sin_len = 16, .sin_family = AF_INET, .sin_port = htons(39123), .sin_addr.s_addr = INADDR_BROADCAST};
    int yes = 1; unsigned size = sizeof yes; assert(!dm_sk_option(udp, SOL_SOCKET, SO_BROADCAST, &yes, &size, 1));
    assert(dm_sk_send(udp, "game datagram", 14, 0, &a, 16) == 14);
    char buffer[64]; struct sockaddr_in source; size = sizeof source;
    assert(dm_sk_recv(udp, buffer, sizeof buffer, 0, &source, &size) == 14 && !strcmp(buffer, "game datagram") && source.sin_addr.s_addr == host_ip);
    int tcp = data_socket(SOCK_STREAM, 0); a.sin_addr.s_addr = host_ip;
    assert(!dm_sk_connect(tcp, &a, 16)); assert(dm_sk_send(tcp, "game stream", 12, 0, NULL, 0) == 12);
    assert(dm_sk_recv(tcp, buffer, 12, MSG_WAITALL, NULL, NULL) == 12 && !strcmp(buffer, "game stream"));
    assert(!dm_sk_close(tcp) && !dm_sk_close(udp));
}
static void begin(const char *ip) {
    setenv("DM_LDN", "1", 1); setenv("DM_LDN_BIND_IP", ip, 1);
    assert(dm_ldn_init() == 0 && dm_ldn_state() == DM_LDN_INIT);
    h_ldn_Attach(&signals);
}
static void state_tests(void) {
    unsetenv("DM_LDN"); assert(dm_ldn_init() != 0 && dm_ldn_state() == DM_LDN_NONE);
    begin("127.0.0.1"); assert(dm_ldn_close(1) == DM_LDN_BAD_STATE);
    assert(dm_ldn_open(1) == 0 && dm_ldn_state() == DM_LDN_AP);
    assert(h_ldn_Policy(0) == 0);
    const char advertise[] = "advertised before room creation";
    assert(dm_ldn_advertise(advertise, sizeof advertise) == 0);
    assert(dm_ldn_advertise(advertise, 385) == DM_LDN_BAD_ARGUMENT);
    assert(dm_ldn_create(&config, &security, NULL, &user, 0, NULL) == 0);
    dm_ldn_info info; dm_ldn_update updates[8];
    assert(dm_ldn_info_get(&info, updates, 8) == 0);
    assert(info.count == 1 && info.capacity == 2 && info.nodes[0].ip == 0x7f000001);
    assert(!memcmp(info.advertise, advertise, sizeof advertise) && info.common.ssid.length == 32);
    assert(updates[0].change == 1);
    assert(dm_ldn_info_get(&info, updates, 8) == 0 && updates[0].change == 0);
    dm_ldn_filter filter = {.id = info.id, .flags = 1 | 2 | 4 | 32, .type = 2};
    assert(matches(&info, &filter, 0)); filter.id.intent.scene++; assert(!matches(&info, &filter, 0));
    filter.id.intent.scene--; filter.type = 3; assert(matches(&info, &filter, 0)); filter.type = 2;
    filter.id.intent.scene++;
    filter.id.intent.scene--; filter.id.session[0] ^= 1; assert(!matches(&info, &filter, 0));
    lan_join join = {0}; join.node = info.nodes[0]; join.node.ip = 0x7f000002; join.node.mac.bytes[5] ^= 1;
    memcpy(join.session, info.id.session, 16); proof_for(&join, &security, join.proof);
    int node = -1;
    join.proof[0] ^= 1; assert(accept_join(&join, htonl(join.node.ip), &node) != 0); join.proof[0] ^= 1;
    assert(h_ldn_Policy(1) == 0 && accept_join(&join, htonl(join.node.ip), &node) != 0);
    assert(h_ldn_Policy(0) == 0 && accept_join(&join, htonl(join.node.ip), &node) == 0 && node == 1);
    assert(accept_join(&join, htonl(join.node.ip), &node) != 0); // duplicate member / full room
    assert(dm_ldn_info_get(&info, updates, 8) == 0 && info.count == 2 && updates[1].change == 1);
    assert(dm_lan_peer(htonl(0x7f000002)) && !dm_lan_peer(htonl(0x7f000003)));
    assert(h_ldn_Reject(0x7f000002) == 0);
    assert(dm_ldn_info_get(&info, updates, 8) == 0 && info.count == 1 && updates[1].change == 2);
    assert(dm_ldn_disconnect(1) == 0 && dm_ldn_state() == DM_LDN_AP);
    assert(dm_ldn_close(1) == 0 && dm_ldn_state() == DM_LDN_INIT);
    dm_ldn_finalize(); assert(dm_ldn_state() == DM_LDN_NONE && signals > 0);
    begin("127.0.0.1"); dm_ldn_finalize(); // repeated init/finalize owns no stale worker or discovery objects
    puts("LDN state, admission, ABI, flags, policies and lifecycle: PASS");
}
static int host(const char *ip, const char *marker) {
    begin(ip); assert(dm_ldn_open(1) == 0); assert(dm_ldn_create(&config, &security, NULL, &user, 0, NULL) == 0);
    int udp = data_socket(SOCK_DGRAM, 39123), tcp = data_socket(SOCK_STREAM, 39123); assert(!dm_sk_listen(tcp, 2));
    FILE *f = fopen(marker, "w"); assert(f); fputs("ready\n", f); fclose(f);
    dm_ldn_info info; int joined = 0;
    for (int i = 0; i < 300; i++) { assert(!dm_ldn_info_get(&info, NULL, 0)); if (info.count == 2) { joined = 1; break; } pause_ms(100); }
    assert(joined); const char data[] = "membership arrived"; assert(dm_ldn_advertise(data, sizeof data) == 0);
    host_data(udp, tcp); dm_sk_finalize();
    int left = 0;
    for (int i = 0; i < 200; i++) { assert(!dm_ldn_info_get(&info, NULL, 0)); if (info.count == 1) { left = 1; break; } pause_ms(100); }
    assert(left); const char ready[] = "rejoin allowed"; assert(!dm_ldn_advertise(ready, sizeof ready));
    joined = 0;
    for (int i = 0; i < 200; i++) { assert(!dm_ldn_info_get(&info, NULL, 0)); if (info.count == 2) { joined = 1; break; } pause_ms(100); }
    assert(joined); assert(!h_ldn_Reject(info.nodes[1].ip));
    const char rejected[] = "rejected member"; assert(!dm_ldn_advertise(rejected, sizeof rejected));
    joined = 0;
    for (int i = 0; i < 200; i++) { assert(!dm_ldn_info_get(&info, NULL, 0)); if (info.count == 2) { joined = 1; break; } pause_ms(100); }
    assert(joined); assert(dm_ldn_disconnect(1) == 0);
    dm_ldn_finalize(); puts("LDN host: discovery, data, leave, rejoin, reject and destroy PASS"); return 0;
}
static int client(const char *ip) {
    begin(ip); assert(dm_ldn_open(0) == 0);
    dm_ldn_filter filter = {.id.intent = config.intent, .flags = 1 | 32}; dm_ldn_info infos[8], info; int count = 0;
    for (int i = 0; i < 15 && !count; i++) assert(dm_ldn_scan(infos, &count, 8, &filter, 0, 0) == 0);
    assert(count); dm_ldn_security bad = security; bad.passphrase[0] ^= 1;
    assert(dm_ldn_connect(&infos[0], &bad, &user, config.version) != 0); // bad credentials never create a node
    assert(dm_ldn_connect(&infos[0], &security, &user, config.version) == 0 && dm_ldn_state() == DM_LDN_CONNECTED);
    int updated = 0;
    for (int i = 0; i < 100; i++) { assert(!dm_ldn_info_get(&info, NULL, 0)); if (info.advertise_size && !strcmp((char *)info.advertise, "membership arrived")) { updated = 1; break; } pause_ms(100); }
    assert(updated && info.count == 2); client_data(htonl(info.nodes[0].ip)); pause_ms(2500); // exercise control-plane keepalive
    assert(dm_ldn_state() == DM_LDN_CONNECTED); assert(dm_ldn_disconnect(0) == 0);
    for (int i = 0; i < 100; i++) {
        assert(!dm_ldn_scan(infos, &count, 8, &filter, 0, 0));
        if (count && !strcmp((char *)infos[0].advertise, "rejoin allowed")) break;
        pause_ms(100);
    }
    assert(count && !strcmp((char *)infos[0].advertise, "rejoin allowed"));
    assert(!dm_ldn_connect(&infos[0], &security, &user, config.version));
    for (int i = 0; i < 100 && dm_ldn_state() == DM_LDN_CONNECTED; i++) pause_ms(50);
    assert(dm_ldn_state() == DM_LDN_STATION && h_ldn_DiscReason() == 5);
    assert(!dm_ldn_connect(&infos[0], &security, &user, config.version));
    for (int i = 0; i < 100 && dm_ldn_state() == DM_LDN_CONNECTED; i++) pause_ms(50);
    assert(dm_ldn_state() == DM_LDN_STATION && h_ldn_DiscReason() == 3); dm_ldn_finalize();
    puts("LDN client: authenticated data, rejoin, rejection and host teardown PASS"); return 0;
}
int main(int argc, char **argv) {
    if (argc == 4 && !strcmp(argv[1], "host")) return host(argv[2], argv[3]);
    if (argc == 3 && !strcmp(argv[1], "client")) return client(argv[2]);
    state_tests(); return 0;
}
