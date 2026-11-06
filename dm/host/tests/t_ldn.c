// LDN state, admission and real two-process Bonjour/TCP control-plane checks.
#include <ifaddrs.h>
static struct ifaddrs *fixture_interfaces;
static int fixture_getifaddrs(struct ifaddrs **out) {
    if (!fixture_interfaces) return getifaddrs(out);
    *out = fixture_interfaces; return 0;
}
static void fixture_freeifaddrs(struct ifaddrs *all) {
    if (all != fixture_interfaces) freeifaddrs(all);
}
#define getifaddrs fixture_getifaddrs
#define freeifaddrs fixture_freeifaddrs
#include "../hle_ldn.c"
#undef getifaddrs
#undef freeifaddrs
#include "../hle_socket.c"
#include <assert.h>
__thread _Atomic int dm_host_work;
static _Atomic unsigned frozen_reasons;
void guest_clock_freeze_for(int reason, int on) {
    if (on) atomic_fetch_or(&frozen_reasons, 1u << reason);
    else atomic_fetch_and(&frozen_reasons, ~(1u << reason));
}
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
static void begin(const char *ip);
static _Atomic int lifecycle_stop;
static void *lifecycle_notifications(void *unused) {
    (void)unused;
    while (!atomic_load(&lifecycle_stop)) {
        dm_lan_background(1); dm_lan_background(0); pause_ms(1);
    }
    return NULL;
}
static void lifecycle_tests(void) {
    pthread_t notifier; assert(!pthread_create(&notifier, NULL, lifecycle_notifications, NULL));
    for (int i = 0; i < 40; i++) { begin("127.0.0.1"); pause_ms(1); dm_ldn_finalize(); }
    atomic_store(&lifecycle_stop, 1); pthread_join(notifier, NULL);
    dm_lan_background(0);
    assert(!atomic_load(&wait_gate) && !(atomic_load(&frozen_reasons) & 8u));
    puts("LDN concurrent lifecycle notifications and repeated finalization PASS");
}
static void wait_state_tests(void) {
    lan_client clients[LAN_MAX_CLIENTS];
    for (int i = 0; i < LAN_MAX_CLIENTS; i++) clients[i].fd = -1;
    uint64_t announced = 0; uint64_t now = lan_ms();
    lan.running = 1; lan.state = DM_LDN_HOST; lan.wait.limit_ms = 30000;
    lan.info.count = lan.info.capacity = 2; lan.info.nodes[0].connected = lan.info.nodes[1].connected = 1;
    lan.wait.capabilities = 1;
    assert(!dm_lan_background(1) && !atomic_load(&wait_gate));
    dm_lan_background(0); lan.wait.capabilities = 3;
    atomic_store(&frozen_reasons, 2u); // Independent system background ownership.
    assert(dm_lan_background(1)); wait_worker(clients, -1, &announced);
    uint64_t deadline = lan.wait.deadline, token = lan.wait.token;
    assert(deadline >= now + 30000 && deadline <= lan_ms() + 30000);
    assert(lan.wait.phase == 1 && lan.wait.away == 1 && atomic_load(&wait_gate));
    wait_host_request(0, 1, now + 10000); // A duplicate never renews the reservation.
    assert(lan.wait.deadline == deadline && lan.wait.token == token);
    wait_host_request(1, 1, now + 15000);
    assert(lan.wait.deadline == deadline && lan.wait.away == 3);
    dm_lan_background(0); wait_worker(clients, -1, &announced);
    assert(lan.wait.phase == 1 && lan.wait.away == 2 && atomic_load(&frozen_reasons) == 10u);
    wait_host_request(1, 0, now + 20000); token = lan.wait.token;
    wait_host_ack(1, token - 1); wait_worker(clients, -1, &announced);
    assert(lan.wait.phase == 2 && atomic_load(&wait_gate)); // A stale ready cannot release the game.
    wait_host_ack(1, token); wait_worker(clients, -1, &announced);
    assert(!lan.wait.phase && !atomic_load(&wait_gate) && atomic_load(&frozen_reasons) == 2u);
    wait_host_request(1, 1, lan_ms()); wait_worker(clients, -1, &announced);
    lan.wait.deadline = lan_ms() - 1; wait_worker(clients, -1, &announced);
    assert(lan.state == DM_LDN_AP && !atomic_load(&wait_gate) && lan.wait.failed_until > lan_ms());
    dm_lan_wait_info info; dm_lan_wait_snapshot(&info); assert(info.state == DM_LAN_WAIT_ENDED);
    lan.state = DM_LDN_HOST; wait_host_request(1, 1, lan_ms()); wait_worker(clients, -1, &announced);
    remove_node(1); wait_worker(clients, -1, &announced);
    assert(lan.state == DM_LDN_AP && !atomic_load(&wait_gate));
    lan.running = 0; lan.state = DM_LDN_NONE; memset(&lan.info, 0, sizeof lan.info); memset(&lan.wait, 0, sizeof lan.wait);
    wait_apply(); atomic_store(&frozen_reasons, 0);
    puts("LDN waiting: compatible members, immutable deadlines, multiple absences, stale acknowledgements, timeout, lost members and independent clock owners PASS");
}
static _Atomic int wait_probe_stop;
static _Atomic unsigned wait_probe_work;
static void *wait_probe(void *unused) {
    (void)unused;
    while (!atomic_load(&wait_probe_stop)) { dm_lan_wait_guest(); atomic_fetch_add(&wait_probe_work, 1); pause_ms(10); }
    return NULL;
}
static int wait_endpoint(int is_host, const char *ip, const char *status, const char *control) {
    begin(ip);
    assert(!dm_ldn_open(is_host));
    if (is_host) assert(!dm_ldn_create(&config, &security, NULL, &user, 0, NULL));
    else {
        dm_ldn_filter filter = {.id.intent = config.intent, .flags = 1 | 32}; dm_ldn_info rooms[8]; int count = 0;
        for (int i = 0; i < 20 && !count; i++) assert(!dm_ldn_scan(rooms, &count, 8, &filter, 0, 0));
        assert(count && !dm_ldn_connect(&rooms[0], &security, &user, config.version));
    }
    FILE *commands = fopen(control, "r"); assert(commands);
    pthread_t probe; assert(!pthread_create(&probe, NULL, wait_probe, NULL));
    int quit = 0; unsigned processed = 0;
    while (!quit) {
        clearerr(commands); char line[80];
        while (fgets(line, sizeof line, commands)) {
            processed++;
            if (!strcmp(line, "background\n")) dm_lan_background(1);
            else if (!strcmp(line, "foreground\n")) dm_lan_background(0);
            else if (!strcmp(line, "cancel\n")) dm_lan_wait_cancel();
            else if (!strcmp(line, "legacy\n")) { pthread_mutex_lock(&lan.lock); lan.wait.capabilities = 1; changed_locked(); pthread_mutex_unlock(&lan.lock); wake_worker(); }
            else if (!strcmp(line, "quit\n")) quit = 1;
            else assert(!"unknown wait test command");
        }
        dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
        char temporary[1024]; snprintf(temporary, sizeof temporary, "%s.new", status);
        FILE *out = fopen(temporary, "w"); assert(out);
        fprintf(out, "{\"state\":%d,\"wait\":%d,\"seconds\":%d,\"supported\":%d,\"background\":%d,\"frozen\":%u,\"work\":%u,\"commands\":%u}\n",
                dm_ldn_state(), info.state, info.seconds, info.supported, info.local_background,
                atomic_load(&frozen_reasons), atomic_load(&wait_probe_work), processed);
        fclose(out); assert(!rename(temporary, status)); pause_ms(20);
    }
    fclose(commands); atomic_store(&wait_probe_stop, 1); dm_ldn_finalize(); pthread_join(probe, NULL);
    assert(!(atomic_load(&frozen_reasons) & 8u)); return 0;
}
static int interface_tests(void) {
    struct sockaddr_in usb = {.sin_len = 16, .sin_family = AF_INET}, wifi = usb, loop = usb;
    struct sockaddr_in linkmask = usb, lanmask = usb;
    inet_pton(AF_INET, "169.254.10.20", &usb.sin_addr);
    inet_pton(AF_INET, "192.168.50.20", &wifi.sin_addr);
    inet_pton(AF_INET, "127.0.0.1", &loop.sin_addr);
    inet_pton(AF_INET, "255.255.0.0", &linkmask.sin_addr);
    inet_pton(AF_INET, "255.255.255.0", &lanmask.sin_addr);
    struct ifaddrs interfaces[3] = {
        {.ifa_name = "en4", .ifa_flags = IFF_UP, .ifa_addr = (void *)&usb, .ifa_netmask = (void *)&linkmask},
        {.ifa_name = "en0", .ifa_flags = IFF_UP, .ifa_addr = (void *)&wifi, .ifa_netmask = (void *)&lanmask},
        {.ifa_name = "lo0", .ifa_flags = IFF_UP, .ifa_addr = (void *)&loop, .ifa_netmask = (void *)&linkmask},
    };
    int checks = 0, failures = 0;
#define CHECK_INTERFACE(ip, mask, label) do { \
    select_ip(); checks++; \
    if (atomic_load(&local_ip) != (ip) || atomic_load(&local_mask) != (mask)) { \
        failures++; fprintf(stderr, "interface selection: %s FAIL\n", label); \
    } \
} while (0)
    unsetenv("DM_LDN_BIND_IP");
    fixture_interfaces = interfaces; interfaces[0].ifa_next = &interfaces[1];
    CHECK_INTERFACE(wifi.sin_addr.s_addr, lanmask.sin_addr.s_addr, "USB link-local before Wi-Fi");
    fixture_interfaces = &interfaces[1]; interfaces[1].ifa_next = &interfaces[0]; interfaces[0].ifa_next = NULL;
    CHECK_INTERFACE(wifi.sin_addr.s_addr, lanmask.sin_addr.s_addr, "Wi-Fi before USB link-local");
    interfaces[1].ifa_flags = 0;
    CHECK_INTERFACE(usb.sin_addr.s_addr, linkmask.sin_addr.s_addr, "ignore down Wi-Fi");
    interfaces[1].ifa_flags = IFF_UP;
    fixture_interfaces = &interfaces[0];
    CHECK_INTERFACE(usb.sin_addr.s_addr, linkmask.sin_addr.s_addr, "link-local-only fallback");
    interfaces[0].ifa_next = &interfaces[1]; interfaces[1].ifa_next = &interfaces[2];
    setenv("DM_LDN_BIND_IP", "169.254.10.20", 1);
    CHECK_INTERFACE(usb.sin_addr.s_addr, linkmask.sin_addr.s_addr, "explicit link-local override");
    setenv("DM_LDN_BIND_IP", "192.168.50.20", 1);
    CHECK_INTERFACE(wifi.sin_addr.s_addr, lanmask.sin_addr.s_addr, "explicit Wi-Fi override");
    setenv("DM_LDN_BIND_IP", "127.0.0.1", 1);
    CHECK_INTERFACE(loop.sin_addr.s_addr, linkmask.sin_addr.s_addr, "explicit loopback test interface");
    setenv("DM_LDN_BIND_IP", "192.168.50.99", 1);
    CHECK_INTERFACE(0, 0, "missing explicit address cannot select another interface");
    unsetenv("DM_LDN_BIND_IP"); interfaces[1].ifa_name = "bridge0";
    CHECK_INTERFACE(usb.sin_addr.s_addr, linkmask.sin_addr.s_addr, "automatic LAN whitelist excludes virtual bridge");
    interfaces[0].ifa_next = NULL; interfaces[0].ifa_flags = 0;
    CHECK_INTERFACE(0, 0, "no active LAN address");
    fixture_interfaces = NULL; atomic_store(&local_ip, 0); atomic_store(&local_mask, 0);
#undef CHECK_INTERFACE
    printf("LDN interface selection: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
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
    setenv("DM_LDN", "1", 1);
    if (!strcmp(ip, "auto")) unsetenv("DM_LDN_BIND_IP");
    else setenv("DM_LDN_BIND_IP", ip, 1);
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
    if (argc == 5 && (!strcmp(argv[1], "wait-host") || !strcmp(argv[1], "wait-client")))
        return wait_endpoint(!strcmp(argv[1], "wait-host"), argv[2], argv[3], argv[4]);
    if (argc == 2 && !strcmp(argv[1], "interfaces")) return interface_tests();
    if (argc == 4 && !strcmp(argv[1], "host")) return host(argv[2], argv[3]);
    if (argc == 3 && !strcmp(argv[1], "client")) return client(argv[2]);
    wait_state_tests();
    if (interface_tests()) return 1;
    state_tests(); lifecycle_tests(); return 0;
}
