// Exercise actual guest-stack entry and ExitThread. A synchronization waiter
// may reclaim the guest stack before pthread_exit and its TLS destructors finish.
#include "../dm.h"
#include <assert.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/mman.h>
#include <unistd.h>
static _Noreturn void observed_exit(void *);
#define pthread_exit observed_exit
#include "../hle_thread.c"
#undef pthread_exit

static _Atomic int exiting, release_exit, destroyed, enter_exit;
static pthread_key_t cleanup_key;
module_t g_mod[MAX_MOD]; int g_nmod;
void hlecount_svc(int num) { (void)num; }
void guest_clock_read_wait(void) {}
uint64_t dm_entropy64(void) { return 0; }
int dm_ue_heap_owns(uint64_t a, uint64_t n) { (void)a; (void)n; return 0; }
void dm_guest_write_prepare(void *addr, size_t size) { (void)addr; (void)size; }
void dm_backtrace(uint64_t fp) { (void)fp; }
uint64_t svc_dispatch(int num, uint64_t *regs, uint64_t origin);
static uint64_t memory(unsigned num, uint64_t a, uint64_t b, uint64_t c) {
    uint64_t r[32] = {a, b, c}; svc_dispatch(num, r, 0); assert(!r[0]); return r[1];
}
static void native_stack(void) {
    uintptr_t sp;
    __asm__ volatile("mov %0, sp" : "=r"(sp));
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
    assert(sp < top && sp >= top - pthread_get_stacksize_np(pthread_self()));
}
static _Noreturn void observed_exit(void *result) {
    native_stack();
    atomic_store(&exiting, 1);
    while (!atomic_load(&release_exit)) sched_yield();
    pthread_exit(result);
}
static void cleanup(void *value) {
    assert(value == &cleanup_key);
    native_stack();
    atomic_fetch_add(&destroyed, 1);
}
static void guest_body(void *stack) {
    memset(stack, 0x75, 64);
    assert(!pthread_setspecific(cleanup_key, &cleanup_key));
    while (!atomic_load(&enter_exit)) sched_yield();
    uint64_t regs[32] = {0};
    svc_thread(0x0a, regs);
    assert(0);
}
// The unrelated static import/gate entries are linked beside dm_thread_enter.
void unimpl_c(void) { abort(); }
uint64_t gate_dispatch(uint64_t ret, uint64_t *regs) { (void)ret; (void)regs; abort(); }
int main(void) {
    alarm(20);
    assert(!pthread_key_create(&g_key18, NULL));
    assert(!pthread_key_create(&cleanup_key, cleanup));
    svc_thread_main_init();
    enum { N = 100, SIZE = 0x100000 };
    uintptr_t source = memory(1, 0, 2 * SIZE, 0), base = memory(0x29, 0, 14, 0);
    for (unsigned i = 0; i < N; ++i) {
        atomic_store(&exiting, 0); atomic_store(&release_exit, 0); atomic_store(&enter_exit, 0);
        void *stack = (void *)(base + (i % 4) * SIZE);
        memset((void *)source, 0x31, SIZE);
        memory(4, (uintptr_t)stack, source, SIZE);
        uint64_t r[32] = {0, (uintptr_t)guest_body, (uintptr_t)stack, (uintptr_t)stack + SIZE, 44, 0};
        assert(svc_thread(8, r) && !r[0]); uint32_t handle = r[1];
        r[0] = handle; assert(svc_thread(9, r) && !r[0]);
        if (i & 1) { r[0] = handle; assert(svc_thread(0x16, r) && !r[0]); }
        atomic_store(&enter_exit, 1);
        if (!(i & 1)) {
            r[0] = 0; r[1] = (uintptr_t)&handle; r[2] = 1; r[3] = UINT64_MAX;
            assert(svc_thread(0x18, r) && !r[0]);
        }
        while (!atomic_load(&exiting)) sched_yield();
        memory(5, (uintptr_t)stack, source, SIZE);
        for (unsigned j = 0; j < 64; ++j) assert(((uint8_t *)source)[j] == 0x75);
        char resident[SIZE / 0x1000];
        assert(!mincore(stack, SIZE, resident));
        for (unsigned j = 0; j < SIZE / (unsigned)getpagesize(); ++j) assert(!(resident[j] & MINCORE_INCORE));
        if (!(i & 1)) { r[0] = handle; assert(svc_thread(0x16, r) && !r[0]); }
        atomic_store(&release_exit, 1);
        while (atomic_load(&destroyed) < (int)i + 1) sched_yield();
    }
    memory(1, 0, 0, 0);
    assert(g_all && !g_all->all);
    puts("100 guest-thread exits: native cleanup, early/late handle close, immediate stack reclamation and TLS destructors passed");
    return 0;
}
