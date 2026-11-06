// Owned ABI harness for the build-specific adapter; no game code or assets.
.text
.p2align 2
.globl _test_view_matrix
_test_view_matrix:
    fmov s3, #0.5
    b _dm_view_matrix
.globl _dm_return_037e5978
_dm_return_037e5978:
    stp s1, s2, [x1]
    ret
.globl _test_view_cache
_test_view_cache:
    stp x29, x30, [sp, #-16]!
    bl _dm_view_cache
    mrs x9, nzcv
    str x9, [x1]
    mov w0, w8
    ldp x29, x30, [sp], #16
    ret
.globl _test_view_scissor
_test_view_scissor:
    stp x19, x30, [sp, #-16]!
    mov x19, x0
    mov x0, x1
    fmov s4, s3
    b _dm_view_scissor
.globl _dm_return_03a308f0
_dm_return_03a308f0:
    stp s3, s2, [x0]
    ldp x19, x30, [sp], #16
    ret
.globl _test_view_capture
_test_view_capture:
    stp x21, x30, [sp, #-32]!
    stp d8, d9, [sp, #16]
    mov x21, x0
    mov x0, x1
    fmov s9, s0
    fmov s8, s1
    fdiv s3, s1, s3
    b _dm_view_capture
.globl _dm_return_03a2eac0
_dm_return_03a2eac0:
    stp s2, s3, [x0]
    ldp d8, d9, [sp, #16]
    ldp x21, x30, [sp], #32
    ret
.globl _test_view_units
_test_view_units:
    b _dm_view_units
.globl _dm_return_01462bb8
_dm_return_01462bb8:
    mov w0, w8
    ret
// Remaining continuations are unused by these fixtures but retain valid links.
.globl _dm_return_037e5a50
_dm_return_037e5a50: ret
.globl _dm_return_037e5a80
_dm_return_037e5a80: ret
.globl _dm_return_013a29a8
_dm_return_013a29a8: ret
.globl _dm_return_013a37c8
_dm_return_013a37c8: ret
.globl _test_view_layout
_test_view_layout:
    stp x21, x30, [sp, #-16]!
    mov x21, x0
    b _dm_view_layout
.globl _dm_return_00268ee4
_dm_return_00268ee4:
    mov w0, w8
    ldp x21, x30, [sp], #16
    ret
.section __DATA,__viewtest,regular
.p2align 4
.globl _dm_code_04a65608
_dm_code_04a65608:
.globl _test_view_vtable
_test_view_vtable:
    .space 0x58
    .quad _dm_code_037e5968


.text
.p2align 2
.globl _test_ui_override
_test_ui_override:
    mov x8,x0
    b _dm_view_ui_override

.globl _dm_return_03268180
_dm_return_03268180:
    add sp, sp, #0xb0
    ret
.globl _dm_return_03a30988
_dm_return_03a30988: ret
.globl _dm_code_00264a10
_dm_code_00264a10: ret
.section __DATA,__viewtest,regular
.p2align 4
.globl _dm_code_049adc80
_dm_code_049adc80: .space 16
.globl _dm_code_0474de58
_dm_code_0474de58: .space 16

.text
.globl _test_footer_match
_test_footer_match:
    stp x29, x30, [sp, #-16]!
    bl _dm_view_footer_match
    mov w0, w8
    ldp x29, x30, [sp], #16
    ret
.globl _test_footer_y
_test_footer_y:
    fmov s3, s0
    b _dm_view_footer_y
.globl _dm_return_0027d7c0
_dm_return_0027d7c0:
    fmov s0, s3
    ret
.globl _test_footer_recalc
_test_footer_recalc:
    mov w3, w1
    b _dm_view_footer_recalc
.globl _dm_return_0027d4c4
_dm_return_0027d4c4:
    ldr d8, [sp], #0x50
    mov w0, w3
    ret
.section __DATA,__viewtest,regular
.p2align 4
.globl _dm_code_049f2b70
_dm_code_049f2b70: .space 16

.text
.p2align 2
.globl _dm_return_0029a18c
_dm_return_0029a18c: ret
// Check the draw callback's full argument and scratch-register contract.
.globl _test_keyboard_window_abi
_test_keyboard_window_abi:
    stp x19, x30, [sp, #-16]!
    mov x19, x1
    mov x1, #257
    mov x2, #514
    mov x3, #771
    mov x4, #1028
    mov x5, #1285
    mov x6, #1542
    mov x7, #1799
    mov x8, #2056
    mov x9, #2313
    mov x10, #2570
    mov x11, #2827
    mov x12, #3084
    mov x13, #3341
    mov x14, #3598
    mov x15, #3855
    mov x16, #4112
    mov x17, #4369
    movi v0.16b, #0x12
    mov v1.16b, v0.16b
    mov v2.16b, v0.16b
    mov v3.16b, v0.16b
    cmp xzr, xzr
    bl _dm_view_keyboard_window
    stp x0, x1, [x19, #0]
    stp x2, x3, [x19, #16]
    stp x4, x5, [x19, #32]
    stp x6, x7, [x19, #48]
    stp x8, x9, [x19, #64]
    stp x10, x11, [x19, #80]
    stp x12, x13, [x19, #96]
    stp x14, x15, [x19, #112]
    stp x16, x17, [x19, #128]
    mrs x9, nzcv
    str x9, [x19, #144]
    stp q0, q1, [x19, #160]
    stp q2, q3, [x19, #192]
    ldp x19, x30, [sp], #16
    ret


.text
.p2align 2
.globl _dm_code_00265220
_dm_code_00265220:
    ldrb w8, [x0, #0x18b]
    cbnz w8, Ltest_transition_uploaded
    mov w8, #1
    strb w8, [x0, #0x18b]
    ldp q0, q1, [x0, #0x80]
    ldr q2, [x0, #0xa0]
    stp q0, q1, [x1]
    str q2, [x1, #0x20]
Ltest_transition_uploaded:
    ret
.globl _test_transition_fast
_test_transition_fast:
    stp x19, x30, [sp, #-32]!
    str x20, [sp, #16]
    mov x19, x0
    mov x20, x1
    mov x0, x1
    add x1, x2, #0x40
    bl _dm_view_transition_fast_call
    ldr x20, [sp, #16]
    ldp x19, x30, [sp], #32
    ret
