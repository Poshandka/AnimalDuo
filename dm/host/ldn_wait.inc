// Coordinated native-port waiting for iOS suspension. This is a bounded platform
// accommodation: every compatible member stops guest time and guest data I/O;
// the native control worker remains independent and can survive process SIGSTOP.
// An expired/missing member ends the session, never fabricates game state.
static pthread_mutex_t wait_effect_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned wait_members_locked(void) {
    unsigned mask = 0;
    for (int i = 0; i < 8; i++) if (lan.info.nodes[i].connected) mask |= 1u << i;
    return mask;
}
static unsigned wait_caps_locked(void) {
    unsigned members = wait_members_locked();
    return LAN_CAP_WAIT | ((members && (lan.wait.capabilities & members) == members) ? LAN_CAP_ROOM_WAIT : 0);
}
static int wait_supported_locked(void) {
    if (lan.info.count < 2) return 0;
    if (lan.state == DM_LDN_HOST) return (wait_caps_locked() & LAN_CAP_ROOM_WAIT) != 0;
    return lan.state == DM_LDN_CONNECTED && (lan.wait.capabilities & 3u) == 3u;
}
static void wait_end_locked(int failed, uint64_t now) {
    if (failed && (lan.wait.phase || lan.wait.local_pending)) lan.wait.failed_until = now + 7000;
    lan.wait.phase = lan.wait.away = lan.wait.acks = 0;
    lan.wait.deadline = lan.wait.pending_deadline = 0;
    lan.wait.local_pending = lan.wait.sent_background = lan.wait.abort = 0;
    pthread_cond_broadcast(&lan.changed);
}
static void wait_apply(void) {
    // Serialize effect application without holding the transport lock across a
    // guest-clock lock. A newer lifecycle event always re-reads current state.
    pthread_mutex_lock(&wait_effect_lock);
    pthread_mutex_lock(&lan.lock);
    int on = lan.running && !lan.stop && (lan.state == DM_LDN_HOST || lan.state == DM_LDN_CONNECTED) &&
             (lan.wait.phase || lan.wait.local_pending);
    pthread_mutex_unlock(&lan.lock);
    if (on) {
        if (!atomic_exchange(&wait_gate, 1)) guest_clock_freeze_for(3, 1);
    } else if (atomic_load(&wait_gate)) {
        guest_clock_freeze_for(3, 0);
        atomic_store(&wait_gate, 0);
        pthread_mutex_lock(&lan.lock); pthread_cond_broadcast(&lan.changed); pthread_mutex_unlock(&lan.lock);
    }
    pthread_mutex_unlock(&wait_effect_lock);
}
void dm_lan_wait_guest(void) {
    if (!atomic_load(&wait_gate)) return;
    dm_thread_native_wait(1);
    pthread_mutex_lock(&lan.lock);
    while (atomic_load(&wait_gate) && lan.running && !lan.stop) pthread_cond_wait(&lan.changed, &lan.lock);
    pthread_mutex_unlock(&lan.lock);
    dm_thread_native_wait(0);
}
int dm_lan_background(int background) {
    pthread_mutex_lock(&lan.lock);
    int supported = lan.running && wait_supported_locked();
    int changed = lan.wait.local_background != !!background, role = lan.state;
    if (changed) {
        lan.wait.local_background = !!background; lan.wait.local_seq++;
        if (background && supported) {
            lan.wait.local_pending = 1; lan.wait.pending_deadline = lan_ms() + 3000;
            lan.wait.failed_until = 0;
        }
    }
    pthread_mutex_unlock(&lan.lock);
    if (changed && (role == DM_LDN_HOST || role == DM_LDN_CONNECTED))
        LOG("ldn: app %s, role %d, coordinated wait %s", background ? "background" : "foreground", role,
            supported ? "supported" : "unavailable");
    wait_apply(); wake_worker(); return supported;
}
void dm_lan_wait_cancel(void) {
    pthread_mutex_lock(&lan.lock);
    if (lan.wait.phase || lan.wait.local_pending) lan.wait.abort = 1;
    pthread_mutex_unlock(&lan.lock); wake_worker();
}
void dm_lan_wait_snapshot(dm_lan_wait_info *out) {
    if (!out) return;
    uint64_t now = lan_ms(); pthread_mutex_lock(&lan.lock);
    *out = (dm_lan_wait_info){.supported = lan.running && wait_supported_locked(),
                            .local_background = lan.wait.local_background, .settling = lan.wait.local_pending};
    if (lan.wait.phase) {
        out->state = lan.wait.phase == 2 ? DM_LAN_WAIT_RESUMING : DM_LAN_WAIT_PAUSED;
        out->seconds = lan.wait.deadline > now ? (int)((lan.wait.deadline - now + 999) / 1000) : 0;
    } else if (lan.wait.local_pending) out->state = DM_LAN_WAIT_PREPARING;
    else if (lan.wait.failed_until > now) out->state = DM_LAN_WAIT_ENDED;
    pthread_mutex_unlock(&lan.lock);
}
static void wait_fail(void) {
    pthread_mutex_lock(&lan.lock);
    wait_end_locked(1, lan_ms());
    if (lan.state == DM_LDN_HOST) { lan.state = DM_LDN_AP; lan.reason = 6; changed_locked(); }
    else if (lan.state == DM_LDN_CONNECTED) {
        lan.state = DM_LDN_STATION; lan.reason = 6; lan.drop_station = 1;
        memset(&lan.info, 0, sizeof lan.info); changed_locked();
    }
    pthread_mutex_unlock(&lan.lock);
    LOG("ldn: coordinated wait ended; the game must leave this session");
    signal_change(); wait_apply(); wake_worker();
}
static void wait_host_request(int node, int background, uint64_t now) {
    pthread_mutex_lock(&lan.lock);
    unsigned bit = 1u << node, members = wait_members_locked();
    if (lan.state != DM_LDN_HOST || !wait_supported_locked() || !(members & bit)) {
        if (!node) lan.wait.local_pending = 0;
        pthread_mutex_unlock(&lan.lock); return;
    }
    unsigned away = background ? lan.wait.away | bit : lan.wait.away & ~bit;
    if (away != lan.wait.away) {
        if (!lan.wait.phase) lan.wait.deadline = now + lan.wait.limit_ms;
        lan.wait.away = away; lan.wait.phase = away ? 1 : 2;
        lan.wait.token++; lan.wait.acks = 1; lan.wait.failed_until = 0;
        LOG("ldn: coordinated wait %s, token %llu, away mask %#x", away ? "paused" : "synchronizing",
            (unsigned long long)lan.wait.token, away);
    } else if (!node && !lan.wait.phase) lan.wait.local_pending = 0; // A cancelled short lifecycle pulse.
    pthread_mutex_unlock(&lan.lock);
}
static int wait_broadcast(lan_client *clients, unsigned op, const lan_hold *hold) {
    int ok = 1;
    for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0 && clients[i].node > 0 &&
        send_frame(clients[i].fd, op, 0, hold, sizeof *hold)) {
        int node = clients[i].node; close(clients[i].fd); clients[i].fd = -1; remove_node(node); ok = 0;
    }
    return ok;
}
static void wait_host_ack(int node, uint64_t token) {
    pthread_mutex_lock(&lan.lock);
    if (node > 0 && lan.wait.phase && token == lan.wait.token) lan.wait.acks |= 1u << node;
    pthread_mutex_unlock(&lan.lock);
}
static int wait_client_frame(int fd, unsigned op, const lan_hold *hold) {
    if (!hold->token || hold->phase < 1 || hold->phase > 2 || hold->remaining_ms > 60000 ||
        hold->reserved[0] || hold->reserved[1] || (hold->phase == 2 && hold->away)) return -1;
    uint64_t now = lan_ms(); int background, ack = 0;
    pthread_mutex_lock(&lan.lock);
    if ((lan.wait.capabilities & 3u) != 3u) { pthread_mutex_unlock(&lan.lock); return -1; }
    if (op == LAN_HOLD) {
        if (!hold->remaining_ms || (hold->phase == 1 && !hold->away)) { pthread_mutex_unlock(&lan.lock); return -1; }
        if (hold->token < lan.wait.token) { pthread_mutex_unlock(&lan.lock); return 0; }
        uint64_t deadline = now + hold->remaining_ms;
        if (!lan.wait.phase || deadline < lan.wait.deadline) lan.wait.deadline = deadline;
        lan.wait.token = hold->token; lan.wait.phase = hold->phase; lan.wait.away = hold->away;
        lan.wait.local_pending = 0; lan.wait.failed_until = 0;
        ack = hold->phase == 1 || !lan.wait.local_background;
    } else {
        if (lan.wait.phase != 2 || hold->phase != 2 || hold->token != lan.wait.token) {
            pthread_mutex_unlock(&lan.lock); return -1;
        }
        if (!lan.wait.local_background) wait_end_locked(0, now);
    }
    background = lan.wait.local_background;
    pthread_mutex_unlock(&lan.lock); wait_apply();
    if (ack && send_frame(fd, LAN_HOLD_ACK, 0, &hold->token, sizeof hold->token)) return -1;
    if (background && hold->phase == 2 && send_frame(fd, LAN_BACKGROUND, 1, NULL, 0)) return -1;
    return 0;
}
// Called after processing readable sockets, before expiry checks. A process that
// resumes after SIGSTOP must consume queued hold/continue frames before treating
// an ordinary stale heartbeat or a negotiation deadline as a failure.
static void wait_worker(lan_client *clients, int station, uint64_t *announced) {
    uint64_t now = lan_ms(); int role, local, changed, supported;
    pthread_mutex_lock(&lan.lock);
    role = lan.state; local = lan.wait.local_background; supported = wait_supported_locked();
    changed = lan.wait.handled_seq != lan.wait.local_seq;
    lan.wait.handled_seq = lan.wait.local_seq;
    if (role != DM_LDN_HOST && role != DM_LDN_CONNECTED) wait_end_locked(1, now);
    pthread_mutex_unlock(&lan.lock);
    if (role != DM_LDN_HOST && role != DM_LDN_CONNECTED) { wait_apply(); return; }
    if (changed) {
        if (role == DM_LDN_HOST) wait_host_request(0, local, now);
        else {
            pthread_mutex_lock(&lan.lock);
            int send = supported && (local || lan.wait.sent_background);
            if (send) lan.wait.sent_background = local;
            else if (!lan.wait.phase) lan.wait.local_pending = 0;
            pthread_mutex_unlock(&lan.lock);
            if (send && (station < 0 || send_frame(station, LAN_BACKGROUND, local, NULL, 0))) { wait_fail(); return; }
        }
    }
    wait_apply();
    pthread_mutex_lock(&lan.lock);
    int fail = lan.wait.abort || (lan.wait.phase && now >= lan.wait.deadline) ||
               (role == DM_LDN_CONNECTED && lan.wait.local_pending && !lan.wait.phase && now >= lan.wait.pending_deadline);
    int phase = lan.wait.phase;
    lan_hold hold = {.token = lan.wait.token, .away = lan.wait.away, .phase = phase,
                     .remaining_ms = lan.wait.deadline > now ? (uint32_t)(lan.wait.deadline - now) : 0};
    pthread_mutex_unlock(&lan.lock);
    if (fail) { wait_fail(); return; }
    if (role == DM_LDN_HOST && phase) {
        if (*announced != hold.token) {
            if (!wait_broadcast(clients, LAN_HOLD, &hold)) { wait_fail(); return; }
            *announced = hold.token;
        }
        pthread_mutex_lock(&lan.lock);
        int all = (lan.wait.acks & wait_members_locked()) == wait_members_locked();
        int proceed = all && phase == 2 && !lan.wait.local_background && lan.wait.handled_seq == lan.wait.local_seq;
        if (all && phase == 1) lan.wait.local_pending = 0;
        pthread_mutex_unlock(&lan.lock);
        if (proceed) {
            if (!wait_broadcast(clients, LAN_CONTINUE, &hold)) { wait_fail(); return; }
            pthread_mutex_lock(&lan.lock);
            if (!lan.wait.local_background && lan.wait.handled_seq == lan.wait.local_seq) wait_end_locked(0, now);
            pthread_mutex_unlock(&lan.lock);
            LOG("ldn: coordinated wait resumed, token %llu", (unsigned long long)hold.token);
            // The acknowledgements are fresh heartbeats at the resume barrier.
            for (int i = 0; i < LAN_MAX_CLIENTS; i++) if (clients[i].fd >= 0 && clients[i].node > 0) clients[i].seen = now;
        }
    }
    wait_apply();
}
