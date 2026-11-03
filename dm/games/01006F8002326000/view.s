// Owned adaptive-view routines for ACNH main ff1d1c05670db6021c85b624a710b963.
// The projection/scissor entry-point lead comes from the MIT-0 ACNH 3.0.X
// Ultrawide project. Vertical coverage and dynamic cache checks are local.
// State +8: target aspect (0 original), +12: folding display capability.
// +24: stable host original-frame counter; +32/+40/+48: native UI frame stamps.
.text
.p2align 2
.globl _dm_view_matrix
_dm_view_matrix:
    ldp s1, s2, [x0, #0xac]
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lmatrix_done
    ldr s6, Lbase
    fcmp s2, s6
    b.ne Lmatrix_done
    fmov s7, w15
    fdiv s6, s6, s7
    fmov s3, #1.0
    fmax s6, s6, s3
    fmul s1, s1, s6
    fmov s2, s7
    fmov s3, #0.5
Lmatrix_done:
    b _dm_return_037e5978

// A cached projection must follow target changes even when the game has not
// changed its own camera parameters. The original dirty byte is returned for
// every other object. No padding or lifetime-sensitive pointers are written.
.globl _dm_view_cache
_dm_view_cache:
    ldrb w8, [x0, #8]
    cbnz w8, Lcache_return
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #12]
    cbz w15, Lcache_return
    stp q0, q1, [sp, #-64]!
    stp q2, q3, [sp, #32]
    mrs x15, nzcv
    str x15, [sp, #-16]!
    ldr x15, [x0]
    adrp x16, _dm_code_04a65608@PAGE
    add x16, x16, _dm_code_04a65608@PAGEOFF
    cmp x15, x16
    b.ne Lcache_done
Lcache_perspective:
    ldr s0, [x0, #0xb0]
Lcache_expected:
    ldr s1, Lbase
    fcmp s0, s1
    b.ne Lcache_done
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lcache_compare
    fmov s0, w15
Lcache_compare:
    ldr s1, [x0, #0xc]
    ldr s2, [x0, #0x20]
    fdiv s1, s2, s1
    fabs s1, s1
    fsub s1, s1, s0
    fabs s1, s1
    ldr s2, Lepsilon
    fmul s2, s0, s2
    fcmp s1, s2
    cset w8, hi
Lcache_done:
    ldr x15, [sp], #16
    msr nzcv, x15
    ldp q2, q3, [sp, #32]
    ldp q0, q1, [sp], #64
Lcache_return:
    ret


// UI jobs can bypass Projection::getMatrix and return a retained override.
// This getter belongs to the screen UI manager. Recognize its verified 40-degree
// lens and 1..10000 depth transform, keeping square/local and off-axis captures
// untouched. X remains canonical; Y is derived afresh, including target zero.
.globl _dm_view_ui_override
_dm_view_ui_override:
    add x0, x8, #8
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Lui_return
    ldr w16, [x0, #0x3c]
    cbnz w16, Lui_return
    ldr w16, [x0, #0x38]
    mov w14, #0xbf800000
    cmp w16, w14
    b.ne Lui_return
    ldr w16, [x0, #0x28]
    ldr w14, Lui_depth_z
    cmp w16, w14
    b.ne Lui_return
    ldr w16, [x0, #0x2c]
    ldr w14, Lui_depth_w
    cmp w16, w14
    b.ne Lui_return
    ldr w16, [x0, #8]
    ldr w14, [x0, #0x18]
    orr w16, w16, w14
    cbnz w16, Lui_return
    ldr s0, [x0]
    ldr s1, [x0, #0x14]
    ldr s2, Lui_x
    ldr s3, Lbase
    ldr s4, Lepsilon
    fsub s2, s0, s2
    fabs s2, s2
    fcmp s2, s4
    b.ls Lui_apply
    // A wider initial target retains the canonical vertical coefficient.
    ldr s2, Lui_x
    fmul s2, s2, s3
    fsub s2, s1, s2
    fabs s2, s2
    fcmp s2, s4
    b.hi Lui_return
    fdiv s0, s1, s3
    str s0, [x0]
Lui_apply:
    ldr w16, [x15, #8]
    cbz w16, Lui_original
    fmov s3, w16
Lui_original:
    fmul s1, s0, s3
    str s1, [x0, #0x14]
Lui_return:
    ret
Lui_x: .float 1.5454561710357666
Lui_depth_z: .float -1.0002000331878662
Lui_depth_w: .float -2.000200033187866

// Scissor conversion follows the current perspective matrix. Capture-local
// orthographic projections retain their native coordinates. Preserve NZCV.
.globl _dm_view_scissor
_dm_view_scissor:
    fdiv s3, s0, s2
    fdiv s2, s1, s4
    stp x15, x16, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lscissor_done
    ldr w16, [x19, #0x4c]
    cbnz w16, Lscissor_done
    stp q5, q6, [sp, #-48]!
    str q7, [sp, #32]
    // Match the actual projection to this layout's reference rectangle.
    ldr s5, [x19, #0x24]
    ldr s6, [x19, #0x10]
    fdiv s5, s5, s6
    fabs s5, s5
    ldr x15, [x19, #0xc0]
    ldp s6, s7, [x15, #0x28]
    fdiv s6, s6, s7
    fdiv s5, s5, s6
    // A target narrower than stock extends Y; a wider target extends X.
    fmov s6, #1.0
    fmin s6, s6, s5
    fmul s2, s2, s6
    fmov s6, #1.0
    fdiv s5, s6, s5
    fmin s5, s5, s6
    fmul s3, s3, s5
    ldr q7, [sp, #32]
    ldp q5, q6, [sp], #48
Lscissor_done:
    ldp x15, x16, [sp], #16
    b _dm_return_03a308f0

.globl _dm_view_capture
_dm_view_capture:
    fdiv s2, s9, s2
    stp x15, x16, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lcapture_done
    ldr w16, [x21, #0x4c]
    cbnz w16, Lcapture_done
    stp q4, q5, [sp, #-48]!
    str q6, [sp, #32]
    ldr s4, [x21, #0x24]
    ldr s5, [x21, #0x10]
    fdiv s4, s4, s5
    fabs s4, s4
    ldr x15, [x21, #0xc0]
    ldp s5, s6, [x15, #0x28]
    fdiv s5, s5, s6
    fdiv s4, s4, s5
    fmov s5, #1.0
    fmin s5, s5, s4
    fmul s3, s3, s5
    fmov s5, #1.0
    fdiv s4, s5, s4
    fmin s4, s4, s5
    fmul s2, s2, s4
    ldr q6, [sp, #32]
    ldp q4, q5, [sp], #48
Lcapture_done:
    ldp x15, x16, [sp], #16
    b _dm_return_03a2eac0

// Field rectangles select which terrain, trees and items are instantiated.
// Extend depth as well as width; the margin covers the five-unit cell grid.
.globl _dm_view_create
_dm_view_create:
    str x15, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lcreate_done
    stp q2, q3, [sp, #-32]!
    fmov s2, w15
    ldr s1, Lbase
    fdiv s0, s1, s2
    fdiv s1, s2, s1
    fmov s2, #1.0
    ldr s3, Lmargin
    fmul s0, s0, s3
    fmax s0, s0, s2
    fmul s1, s1, s3
    fmax s1, s1, s2
    fmul s8, s8, s0
    fmul s12, s12, s0
    fmul s9, s9, s1
    fmul s13, s13, s1
    ldr s2, [sp, #0x48]
    fmul s2, s2, s1
    str s2, [sp, #0x48]
    ldp q2, q3, [sp], #32
Lcreate_done:
    ldr x15, [sp], #16
    fsub s0, s10, s9
    b _dm_return_013a29a8

.globl _dm_view_area
_dm_view_area:
    str x15, [sp, #-32]!
    str q7, [sp, #16]
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Larea_done
    stp q1, q2, [sp, #-32]!
    fmov s2, w15
    ldr s7, Lbase
    fdiv s0, s7, s2
    fdiv s1, s2, s7
    ldr s7, Lmargin
    fmul s0, s0, s7
    fmul s1, s1, s7
    fmov s7, #1.0
    fmax s0, s0, s7
    fmax s1, s1, s7
    fmul s10, s10, s0
    fmul s11, s11, s0
    fmul s8, s8, s1
    fmul s9, s9, s1
    ldp q1, q2, [sp], #32
Larea_done:
    ldr q7, [sp, #16]
    ldr x15, [sp], #32
    ldr s0, [x20]
    ret

.globl _dm_view_units
_dm_view_units:
    ldr w8, [x0]
    str x15, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #12]
    cbz w15, Lunits_done
    lsl w8, w8, #1
Lunits_done:
    ldr x15, [sp], #16
    b _dm_return_01462bb8


// Near-plane unprojection follows the adapted matrix without mutating camera parameters.
.globl _dm_view_near_y
_dm_view_near_y:
    ldr s1, [x0, #0xac]
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lnear_y_done
    ldr s6, Lbase
    ldr s7, [x0, #0xb0]
    fcmp s6, s7
    b.ne Lnear_y_done
    fmov s7, w15
    fdiv s6, s6, s7
    fmov s16, #1.0
    fmax s6, s6, s16
    fmul s1, s1, s6
Lnear_y_done:
    b _dm_return_037e5a50

.globl _dm_view_near_xy
_dm_view_near_xy:
    ldp s2, s3, [x0, #0xac]
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lnear_xy_done
    ldr s6, Lbase
    fcmp s6, s3
    b.ne Lnear_xy_done
    fmov s7, w15
    fdiv s6, s6, s7
    fmov s16, #1.0
    fmax s6, s6, s16
    fmul s2, s2, s6
    fmov s3, s7
Lnear_xy_done:
    b _dm_return_037e5a80

.globl _dm_view_sphere
_dm_view_sphere:
    str x15, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w15, [x15, #8]
    cbz w15, Lsphere_original
    fmul s2, s0, s0
    fmadd s2, s1, s1, s2
    fmadd s2, s13, s13, s2
    fsqrt s2, s2
    fmul s0, s2, s9
    b Lsphere_done
Lsphere_original:
    fcmp s0, s1
    fcsel s0, s0, s1, gt
    fcmp s13, s0
    fcsel s0, s13, s0, gt
    fmul s0, s0, s9
Lsphere_done:
    ldr x15, [sp], #16
    b _dm_return_013a37c8

.p2align 2
Lbase: .float 1.7777777777777777778
Lmin_width: .float 1280.0
Lmargin: .float 1.1
Lepsilon: .float 0.00001

// The minimap captures already clip at their own render-target edges. Their
// extra screen-space ScissorOn pane was authored for a 16:9 projection and
// trims the captured terrain after changing that projection. Remove only
// that redundant registration, on two exact whole-resource fingerprints.
// Resource bytes remain in the game's writable load buffer; disk is untouched.
.p2align 2
.globl _dm_view_layout
_dm_view_layout:
    stp x9, x10, [sp, #-80]!
    stp x11, x12, [sp, #16]
    stp x13, x14, [sp, #32]
    stp x15, x16, [sp, #48]
    str x17, [sp, #64]
    mrs x17, nzcv
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Llayout_done
    ldr w9, [x21]
    ldr w10, Lflyt_magic
    cmp w9, w10
    b.ne Llayout_done
    ldr w9, [x21, #0xc]
    mov w10, #14012
    cmp w9, w10
    b.eq Llayout_minimap
    mov w10, #11108
    cmp w9, w10
    b.ne Llayout_done
    ldr x13, Lcloud_map_hash
    mov x14, #3292
    b Llayout_hash
Llayout_minimap:
    ldr x13, Lmap_hash
    mov x14, #2908
Llayout_hash:
    mov x10, x21
    ldr x11, Lfnv_offset
    ldr x12, Lfnv_prime
Llayout_byte:
    ldrb w8, [x10], #1
    eor x11, x11, x8
    mul x11, x11, x12
    sub w9, w9, #1
    cbnz w9, Llayout_byte
    cmp x11, x13
    b.ne Llayout_done
    str wzr, [x21, x14]
    mov w16, #1
    str w16, [x15, #16]
Llayout_done:
    msr nzcv, x17
    ldr x17, [sp, #64]
    ldp x15, x16, [sp, #48]
    ldp x13, x14, [sp, #32]
    ldp x11, x12, [sp, #16]
    ldp x9, x10, [sp], #80
    ldrh w8, [x21, #6]
    b _dm_return_00268ee4
.p2align 3
Lmap_hash: .quad 0x1e453d087f41e3bf
Lcloud_map_hash: .quad 0xb7299d38fd75c925
Lfnv_offset: .quad 0xcbf29ce484222325
Lfnv_prime: .quad 0x100000001b3
Lflyt_magic: .word 0x54594c46

// Mark only actual native UI render jobs. No retained game-object pointers are
// exposed to the host; old stamps expire after two original presents.
.p2align 2
.globl _dm_view_keyboard_frame
_dm_view_keyboard_frame:
    stp x15, x16, [sp, #-32]!
    stp x17, x30, [sp, #16]
    mov x17, #32
    bl Ltouch_stamp
    ldp x17, x30, [sp, #16]
    ldp x15, x16, [sp], #32
    sub sp, sp, #0xb0
    b _dm_return_03268180

.globl _dm_view_touch_page
_dm_view_touch_page:
    stp x14, x15, [sp, #-48]!
    stp x16, x17, [sp, #16]
    stp x13, x30, [sp, #32]
    mrs x13, nzcv
    ldr x14, [x0]
    adrp x16, _dm_code_049adc80@PAGE
    add x16, x16, _dm_code_049adc80@PAGEOFF
    cmp x14, x16
    b.ne Ltouch_page_done
    mov x17, #40
    bl Ltouch_stamp
Ltouch_page_done:
    msr nzcv, x13
    ldp x13, x30, [sp, #32]
    ldp x16, x17, [sp, #16]
    ldp x14, x15, [sp], #48
    ret
Ltouch_stamp:
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr x16, [x15, #24]
    cbz x16, Ltouch_stamp_done
    ldar x16, [x16]
    add x16, x16, #1
    add x15, x15, x17
    stlr x16, [x15]
Ltouch_stamp_done:
    ret

// Only the keyboard docks the whole UI projection. Drawing tools retain
// their original centred composition; KeyGuide has its own lower-edge anchor.
// x15 = state, w8 = recently rendered inline keyboard.
Lrecent_keyboard:
    ldr x16, [x15, #24]
    mov w8, wzr
    cbz x16, Lrecent_done
    ldar x16, [x16]
    add x16, x16, #1
    ldr x17, [x15, #32]
    cbz x17, Lrecent_done
    sub x17, x16, x17
    cmp x17, #2
    b.hi Lrecent_done
    mov w8, #1
Lrecent_done:
    ret

// DrawInfo owns a fresh copy of the source projection at this boundary. Dock
// native touch panels to the bottom without moving the 3D camera or accumulating
// translation in a retained source matrix. Local captures keep their projection.
.globl _dm_view_ui_projection
_dm_view_ui_projection:
    stp x0, x30, [sp, #-16]!
    add x0, x0, #0x10
    bl _dm_view_panel_projection
    ldp x0, x30, [sp], #16
    ret
.globl _dm_view_panel_projection
_dm_view_panel_projection:
    stp x15, x30, [sp, #-16]!
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Lpanel_done
    ldr w16, [x0, #0x3c]
    cbnz w16, Lpanel_done
    ldr w16, [x0, #0x38]
    mov w14, #0xbf800000
    cmp w16, w14
    b.ne Lpanel_done
    ldr w16, [x0, #0x28]
    ldr w14, Lui_depth_z
    cmp w16, w14
    b.ne Lpanel_done
    ldr w16, [x0, #0x2c]
    ldr w14, Lui_depth_w
    cmp w16, w14
    b.ne Lpanel_done
    ldr w16, [x0, #8]
    ldr w14, [x0, #0x18]
    orr w16, w16, w14
    cbnz w16, Lpanel_done
    ldr s0, [x0]
    ldr s1, Lui_x
    fsub s1, s0, s1
    fabs s1, s1
    ldr s2, Lepsilon
    fcmp s1, s2
    b.hi Lpanel_done
    ldr s1, Lbase
    ldr w16, [x15, #8]
    cbz w16, Lpanel_ratio
    fmov s1, w16
Lpanel_ratio:
    fmul s0, s0, s1
    str s0, [x0, #0x14]
    ldr s2, Lbase
    fcmp s1, s2
    b.ge Lpanel_done
    bl Lrecent_keyboard
    cbz w8, Lpanel_done
    fdiv s1, s1, s2
    fmov s2, #1.0
    fsub s1, s2, s1
    str s1, [x0, #0x18]
Lpanel_done:
    ldp x15, x30, [sp], #16
    ret

// Scissor rectangles use the layout's centre rather than the projection's
// off-axis term. Apply that same bottom-docking translation to their origin.
.globl _dm_view_scissor_origin
_dm_view_scissor_origin:
    ldp s5, s6, [x8, #8]
    stp x14, x15, [sp, #-32]!
    stp x16, x17, [sp, #16]
    stp q0, q7, [sp, #-48]!
    str q16, [sp, #32]
    mrs x17, nzcv
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Lscissor_origin_done
    ldr w16, [x19, #0x4c]
    cbnz w16, Lscissor_origin_done
    ldr s7, [x19, #0x10]
    ldr s16, [x19, #0x24]
    fdiv s16, s16, s7
    ldr s7, Lbase
    fdiv s16, s16, s7
    fmov s7, #1.0
    fsub s16, s7, s16
    ldr s7, [x19, #0x28]
    fcmp s7, #0.0
    b.le Lscissor_origin_done
    fsub s0, s7, s16
    fabs s0, s0
    ldr s16, Lepsilon
    fcmp s0, s16
    b.hi Lscissor_origin_done
    fmov s16, #0.5
    fmul s7, s7, s6
    fmul s7, s7, s16
    fsub s2, s2, s7
Lscissor_origin_done:
    msr nzcv, x17
    ldr q16, [sp, #32]
    ldp q0, q7, [sp], #48
    ldp x16, x17, [sp, #16]
    ldp x14, x15, [sp], #32
    b _dm_return_03a30988

// Background and iris coverage constants are private to this draw; the pane,
// layout and resource are untouched. Only full-screen centred backgrounds
// expand their repeating UVs with the quad, retaining the pattern density.
.globl _dm_view_backdrop_call
_dm_view_backdrop_call:
    stp x1, x30, [sp, #-16]!
    bl _dm_code_00264a10
    ldr x2, [sp]
    mov x0, x19
    mov x1, x20
    bl _dm_view_backdrop
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret
.globl _dm_view_backdrop
_dm_view_backdrop:
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Lbackdrop_done
    ldr w16, [x15, #8]
    cbz w16, Lbackdrop_done
    // WipeCircle's animated side curtains have fixed reference-screen height.
    // Their widths and translations close the iris and must stay untouched.
    ldr x16, [x0, #0xb0]
    and x16, x16, #0xfffffeffffffffff
    ldr x14, Lwipe_left_name
    cmp x16, x14
    b.eq Lwipe_side
    ldr x14, Lwipe_right_name
    cmp x16, x14
    b.eq Lwipe_side
    ldrb w16, [x0, #0x5b]
    and w16, w16, #15
    cbnz w16, Lbackdrop_done
    ldr w16, [x0, #0xb0]
    ldr w14, Lbg_name
    cmp w16, w14
    b.eq Lbackdrop_size
    ldr w14, Lbg_lower_name
    cmp w16, w14
    b.eq Lbackdrop_size
    ldr w14, Ldot_name
    cmp w16, w14
    b.eq Lbackdrop_size
    ldr w14, Lcolor_bg_name
    cmp w16, w14
    b.eq Lbackdrop_size
    ldr w14, Lall_bg_name
    cmp w16, w14
    b.eq Lbackdrop_size
    ldr w14, Lstripe_name
    cmp w16, w14
    b.ne Lbackdrop_done
Lbackdrop_size:
    mov w11, wzr
    ldp s0, s1, [x0, #0x50]
    ldr x16, [x1, #0xc0]
    cbz x16, Lbackdrop_done
    ldp s2, s3, [x16, #0x28]
    fcmp s0, s2
    b.ne Lbackdrop_done
    fcmp s1, s3
    b.ne Lbackdrop_done
Lbackdrop_projection:
    ldr w16, [x1, #0x4c]
    cbnz w16, Lbackdrop_done
    ldr s2, [x1, #0x24]
    ldr s3, [x1, #0x10]
    fdiv s2, s2, s3
    ldr s3, Lbase
    fdiv s2, s2, s3
    fcmp s2, #0.0
    b.le Lbackdrop_done
    fmov s3, #1.0
    fcmp s2, s3
    b.ge Lbackdrop_done
    fdiv s3, s3, s2
    fmul s4, s1, s3
    str s4, [x2, #0x214]
    fmov s5, #0.5
    fsub s4, s4, s1
    fmul s4, s4, s5
    ldr s6, [x1, #0x28]
    fmul s6, s6, s1
    fmul s6, s6, s3
    fmadd s4, s6, s5, s4
    ldr s5, [x2, #0x21c]
    fadd s4, s4, s5
    str s4, [x2, #0x21c]
    cbnz w11, Lbackdrop_done
    // UV rows use {u,v,0,1}. Keep their midpoint while extending the
    // repeated picture, so dots and stripes retain their original shape.
    mov x16, #0xe4
    mov w14, #3
    mov x13, #0x188
    ldrb w12, [x0, #0xf1]
Lbackdrop_uv:
    // The uniform has three slots, but only active texture-coordinate
    // indices were populated by the original SDK call.
    ldrsb w17, [x1, x13]
    cmp w17, w12
    b.hs Lbackdrop_next_uv
    ldr s0, [x2, x16]
    add x17, x16, #32
    ldr s1, [x2, x17]
    fsub s1, s1, s0
    fmov s2, #0.5
    fmov s4, s3
    fmov s5, #1.0
    fsub s4, s4, s5
    fmul s4, s4, s2
    fmul s4, s4, s1
    fsub s0, s0, s4
    str s0, [x2, x16]
    add x17, x16, #16
    ldr s0, [x2, x17]
    fsub s0, s0, s4
    str s0, [x2, x17]
    add x17, x16, #32
    ldr s0, [x2, x17]
    fadd s0, s0, s4
    str s0, [x2, x17]
    add x17, x16, #48
    ldr s0, [x2, x17]
    fadd s0, s0, s4
    str s0, [x2, x17]
Lbackdrop_next_uv:
    add x13, x13, #1
    add x16, x16, #64
    subs w14, w14, #1
    b.ne Lbackdrop_uv
Lbackdrop_done:
    ret
.p2align 3
Lwipe_left_name: .asciz "P_L_00"
    .byte 0
Lwipe_right_name: .asciz "P_R_00"
    .byte 0
Lwipe_circle_name: .ascii "P_Circle"
Lwipe_inout_name: .ascii "N_InOut_"
Lwipe_root_name: .ascii "RootPane"
Lwipe_root_size: .float 1920.0, 1080.0
Lwipe_inout_size: .float 30.0, 30.0
.p2align 2
Lwipe_side:
    ldr x17, [x0, #0x18]
    cbz x17, Lbackdrop_done
    ldr x16, [x17, #0xb0]
    ldr x14, Lwipe_circle_name
    cmp x16, x14
    b.ne Lbackdrop_done
    // Require a complete matching _00/_01 suffix, including the terminator.
    ldr w16, [x17, #0xb8]
    ldrb w13, [x0, #0xb5]
    lsl w13, w13, #16
    mov w14, #0x305f
    orr w14, w14, w13
    cmp w16, w14
    b.ne Lbackdrop_done
    ldr x17, [x17, #0x18]
    cbz x17, Lbackdrop_done
    ldr x16, [x17, #0xb0]
    ldr x14, Lwipe_inout_name
    cmp x16, x14
    b.ne Lbackdrop_done
    ldr w16, [x17, #0xb8]
    ldrb w13, [x0, #0xb5]
    lsl w13, w13, #8
    mov w14, #0x30
    orr w14, w14, w13
    cmp w16, w14
    b.ne Lbackdrop_done
    ldr x16, [x17, #0x50]
    ldr x14, Lwipe_inout_size
    cmp x16, x14
    b.ne Lbackdrop_done
    ldr x17, [x17, #0x18]
    cbz x17, Lbackdrop_done
    ldr x16, [x17, #0xb0]
    ldr x14, Lwipe_root_name
    cmp x16, x14
    b.ne Lbackdrop_done
    ldrb w16, [x17, #0xb8]
    cbnz w16, Lbackdrop_done
    ldr x16, [x17, #0x50]
    ldr x14, Lwipe_root_size
    cmp x16, x14
    b.ne Lbackdrop_done
    ldr x17, [x1, #0xc0]
    cbz x17, Lbackdrop_done
    ldr x16, [x17, #0x28]
    cmp x16, x14
    b.ne Lbackdrop_done
    ldr s1, [x0, #0x54]
    ldr s2, [x17, #0x2c]
    fcmp s1, s2
    b.ne Lbackdrop_done
    ldr s2, [x2, #0x214]
    fcmp s1, s2
    b.ne Lbackdrop_done
    // These black coverage panes have no repeated-picture UV expansion.
    mov w11, #1
    b Lbackdrop_projection
Lbg_name: .ascii "P_BG"
Lbg_lower_name: .ascii "P_Bg"
Ldot_name: .ascii "P_Do"
Lcolor_bg_name: .ascii "P_Co"
Lall_bg_name: .ascii "P_Al"
Lstripe_name: .ascii "P_St"

// KeyGuide and VideogameKeyGuide share this verified operation-guide hierarchy:
// RootPane(1920x1080) -> N_InOut_00(30x30) -> N_Align_00(1810x100).
// Match all three shapes and both complete child names before changing its
// calculated translation. Original pane coordinates and animations stay intact.
.p2align 2
.globl _dm_view_footer_match
_dm_view_footer_match:
    mov w8, wzr
    ldr x14, [x0, #0xb0]
    ldr x15, Lfooter_inout
    cmp x14, x15
    b.ne Lfooter_match_done
    ldr w14, [x0, #0xb8]
    mov w15, #0x3030
    cmp w14, w15
    b.ne Lfooter_match_done
    ldr x14, [x0, #0x50]
    ldr x15, Lfooter_size
    cmp x14, x15
    b.ne Lfooter_match_done
    ldr x17, [x0, #0x18]
    cbz x17, Lfooter_match_done
    ldr x14, [x17, #0x50]
    ldr x15, Lfooter_root_size
    cmp x14, x15
    b.ne Lfooter_match_done
    ldr x17, [x0, #0x28]
    add x14, x0, #0x20
    cmp x17, x14
    b.eq Lfooter_match_done
    cbz x17, Lfooter_match_done
    sub x17, x17, #8
    ldr x14, [x17, #0xb0]
    ldr x15, Lfooter_align
    cmp x14, x15
    b.ne Lfooter_match_done
    ldr w14, [x17, #0xb8]
    mov w15, #0x3030
    cmp w14, w15
    b.ne Lfooter_match_done
    ldr x14, [x17, #0x50]
    ldr x15, Lfooter_align_size
    cmp x14, x15
    cset w8, eq
Lfooter_match_done:
    ret

// Recalculate this small subtree even when animations are idle, so folding,
// entering/exiting the inline keyboard and Fit restore the footer immediately.
.globl _dm_view_footer_recalc
_dm_view_footer_recalc:
    stp x8, x30, [sp, #-48]!
    stp x14, x15, [sp, #16]
    stp x16, x17, [sp, #32]
    mrs x16, nzcv
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w17, [x15, #12]
    cbz w17, Lfooter_recalc_done
    bl _dm_view_footer_match
    cbz w8, Lfooter_recalc_done
    orr w3, w3, #1
Lfooter_recalc_done:
    msr nzcv, x16
    ldp x16, x17, [sp, #32]
    ldp x14, x15, [sp, #16]
    ldp x8, x30, [sp], #48
    str d8, [sp, #-0x50]!
    b _dm_return_0027d4c4

.globl _dm_view_footer_y
_dm_view_footer_y:
    stp x8, x30, [sp, #-64]!
    stp x14, x15, [sp, #16]
    stp x16, x17, [sp, #32]
    str x13, [sp, #48]
    stp q0, q1, [sp, #-32]!
    mrs x13, nzcv
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w17, [x15, #12]
    cbz w17, Lfooter_y_done
    bl _dm_view_footer_match
    cbz w8, Lfooter_y_done
    adrp x15, _dm_view_state@PAGE
    add x15, x15, _dm_view_state@PAGEOFF
    ldr w16, [x15, #12]
    cbz w16, Lfooter_y_done
    ldr w16, [x15, #8]
    cbz w16, Lfooter_y_done
    ldr s0, Lbase
    fmov s1, w16
    fcmp s1, s0
    b.ge Lfooter_y_done
    bl Lrecent_keyboard
    cbnz w8, Lfooter_y_done
    fdiv s0, s0, s1
    fmov s1, #1.0
    fsub s0, s0, s1
    ldr s1, Lfooter_half_height
    fmsub s3, s0, s1, s3
Lfooter_y_done:
    msr nzcv, x13
    ldp q0, q1, [sp], #32
    ldr x13, [sp, #48]
    ldp x16, x17, [sp, #32]
    ldp x14, x15, [sp, #16]
    ldp x8, x30, [sp], #64
    lsr w10, w10, #6
    b _dm_return_0027d7c0
.p2align 3
Lfooter_inout: .ascii "N_InOut_"
Lfooter_align: .ascii "N_Align_"
Lfooter_size: .float 30.0, 30.0
Lfooter_root_size: .float 1920.0, 1080.0
Lfooter_align_size: .float 1810.0, 100.0
Lfooter_half_height: .float 540.0
