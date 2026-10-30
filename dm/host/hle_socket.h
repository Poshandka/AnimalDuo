// Horizon BSD sockets over the active LDN session. Descriptors are guest-owned,
// never raw host descriptors. Public Internet, name resolution and SSL stay offline.
#pragma once
#include <stdint.h>
extern __thread int dm_sk_errno;
int dm_sk_socket(int, int, int);
int dm_sk_close(int);
void dm_sk_finalize(void);
int dm_sk_bind(int, const void *, unsigned);
int dm_sk_connect(int, const void *, unsigned);
int dm_sk_listen(int, int);
int dm_sk_accept(int, void *, unsigned *);
int dm_sk_name(int, void *, unsigned *, int);
int dm_sk_option(int, int, int, void *, unsigned *, int);
int dm_sk_fcntl(int, int, int);
int dm_sk_shutdown(int, int);
long dm_sk_send(int, const void *, uint64_t, int, const void *, unsigned);
long dm_sk_recv(int, void *, uint64_t, int, void *, unsigned *);
int dm_sk_poll(void *, uint64_t, int);
int dm_sk_select(int, uint64_t *, uint64_t *, uint64_t *, const int64_t *);
