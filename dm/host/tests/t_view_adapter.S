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
