# ACNH 3.0.3 adaptive view; all sites are keyed by the verified main build.
import struct
from pathlib import Path
import hashlib
from nso_asm import B, STP_PRE, LDP_POST, STRX, relocated_words

# BEGIN GENERATED VIEW CODE
# Generated from view.s by dm/tools/gen_view_stubs.py; do not edit.
source_sha256 = '61f803b8bfd8265e71bf4aec77719592c0260690a85bdf32ca35077f224e7b2c'
words = [
    0x2d558801, 0x9000000f, 0x910001ef, 0xb94009ef, 0x3400016f, 0x1c002186,
    0x1e262040, 0x54000101, 0x1e2701e7, 0x1e2718c6, 0x1e2e1003, 0x1e2348c6,
    0x1e260821, 0x1e2040e2, 0x1e2c1003, 0x14000000, 0x39402008, 0x350004a8,
    0x9000000f, 0x910001ef, 0xb9400def, 0x3400042f, 0xadbe07e0, 0xad010fe2,
    0xd53b420f, 0xf81f0fef, 0xf940000f, 0x90000010, 0x91000210, 0xeb1001ff,
    0x54000281, 0xbd40b000, 0x1c001e21, 0x1e212000, 0x54000201, 0x9000000f,
    0x910001ef, 0xb94009ef, 0x3400004f, 0x1e2701e0, 0xbd400c01, 0xbd402002,
    0x1e211841, 0x1e20c021, 0x1e203821, 0x1e20c021, 0x1c001cc2, 0x1e220802,
    0x1e222020, 0x1a9f97e8, 0xf84107ef, 0xd51b420f, 0xad410fe2, 0xacc207e0,
    0xd65f03c0, 0x91002100, 0x9000000f, 0x910001ef, 0xb9400df0, 0x34000530,
    0xb9403c10, 0x350004f0, 0xb9403810, 0x52b7f00e, 0x6b0e021f, 0x54000461,
    0xb9402810, 0x1800046e, 0x6b0e021f, 0x540003e1, 0xb9402c10, 0x1800040e,
    0x6b0e021f, 0x54000361, 0xb9400810, 0xb940180e, 0x2a0e0210, 0x350002f0,
    0xbd400000, 0xbd401401, 0x1c0002a2, 0x1c001803, 0x1c001844, 0x1e223802,
    0x1e20c042, 0x1e242040, 0x54000129, 0x1c0001c2, 0x1e230842, 0x1e223822,
    0x1e20c042, 0x1e242040, 0x54000108, 0x1e231820, 0xbd000000, 0xb94009f0,
    0x34000050, 0x1e270203, 0x1e230801, 0xbd001401, 0xd65f03c0, 0x3fc5d182,
    0xbf80068e, 0xc0000347, 0x1e221803, 0x1e241822, 0xa9bf43ef, 0x9000000f,
    0x910001ef, 0xb94009ef, 0x340002cf, 0xb9404e70, 0x35000290, 0xadbe9be5,
    0x3d800be7, 0xbd402665, 0xbd401266, 0x1e2618a5, 0x1e20c0a5, 0xf940626f,
    0x2d451de6, 0x1e2718c6, 0x1e2618a5, 0x1e2e1006, 0x1e2558c6, 0x1e260842,
    0x1e2e1006, 0x1e2518c5, 0x1e2658a5, 0x1e250863, 0x3dc00be7, 0xacc19be5,
    0xa8c143ef, 0x14000000, 0x1e221922, 0xa9bf43ef, 0x9000000f, 0x910001ef,
    0xb94009ef, 0x340002cf, 0xb9404eb0, 0x35000290, 0xadbe97e4, 0x3d800be6,
    0xbd4026a4, 0xbd4012a5, 0x1e251884, 0x1e20c084, 0xf94062af, 0x2d4519e5,
    0x1e2618a5, 0x1e251884, 0x1e2e1005, 0x1e2458a5, 0x1e250863, 0x1e2e1005,
    0x1e2418a4, 0x1e255884, 0x1e240842, 0x3dc00be6, 0xacc197e4, 0xa8c143ef,
    0x14000000, 0xf81f0fef, 0x9000000f, 0x910001ef, 0xb94009ef, 0x3400028f,
    0xadbf0fe2, 0x1e2701e2, 0x1c000ce1, 0x1e221820, 0x1e211841, 0x1e2e1002,
    0x1c000ca3, 0x1e230800, 0x1e224800, 0x1e230821, 0x1e224821, 0x1e200908,
    0x1e20098c, 0x1e210929, 0x1e2109ad, 0xbd404be2, 0x1e210842, 0xbd004be2,
    0xacc10fe2, 0xf84107ef, 0x1e293940, 0x14000000, 0xf81e0fef, 0x3d8007e7,
    0x9000000f, 0x910001ef, 0xb94009ef, 0x3400022f, 0xadbf0be1, 0x1e2701e2,
    0x1c000967, 0x1e2218e0, 0x1e271841, 0x1c000947, 0x1e270800, 0x1e270821,
    0x1e2e1007, 0x1e274800, 0x1e274821, 0x1e20094a, 0x1e20096b, 0x1e210908,
    0x1e210929, 0xacc10be1, 0x3dc007e7, 0xf84207ef, 0xbd400280, 0xd65f03c0,
    0xb9400008, 0xf81f0fef, 0x9000000f, 0x910001ef, 0xb9400def, 0x3400004f,
    0x531f7908, 0xf84107ef, 0x14000000, 0xbd40ac01, 0x9000000f, 0x910001ef,
    0xb94009ef, 0x3400014f, 0x1c000566, 0xbd40b007, 0x1e2720c0, 0x540000c1,
    0x1e2701e7, 0x1e2718c6, 0x1e2e1010, 0x1e3048c6, 0x1e260821, 0x14000000,
    0x2d558c02, 0x9000000f, 0x910001ef, 0xb94009ef, 0x3400014f, 0x1c000386,
    0x1e2320c0, 0x540000e1, 0x1e2701e7, 0x1e2718c6, 0x1e2e1010, 0x1e3048c6,
    0x1e260842, 0x1e2040e3, 0x14000000, 0xf81f0fef, 0x9000000f, 0x910001ef,
    0xb94009ef, 0x340000ef, 0x1e200802, 0x1f010822, 0x1f0d09a2, 0x1e21c042,
    0x1e290840, 0x14000006, 0x1e212000, 0x1e21cc00, 0x1e2021a0, 0x1e20cda0,
    0x1e290800, 0xf84107ef, 0x14000000, 0x3fe38e39, 0x44a00000, 0x3f8ccccd,
    0x3727c5ac, 0xa9bb2be9, 0xa90133eb, 0xa9023bed, 0xa90343ef, 0xf90023f1,
    0xd53b4211, 0x9000000f, 0x910001ef, 0xb9400df0, 0x340003d0, 0xb94002a9,
    0x1800058a, 0x6b0a013f, 0x54000341, 0xb9400ea9, 0x5286d78a, 0x6b0a013f,
    0x540000e0, 0x52856c8a, 0x6b0a013f, 0x54000261, 0x5800038d, 0xd2819b8e,
    0x14000003, 0x580002ed, 0xd2816b8e, 0xaa1503ea, 0x5800030b, 0x5800032c,
    0x38401548, 0xca08016b, 0x9b0c7d6b, 0x51000529, 0x35ffff89, 0xeb0d017f,
    0x54000081, 0xb82e6abf, 0x52800030, 0xb90011f0, 0xd51b4211, 0xf94023f1,
    0xa94343ef, 0xa9423bed, 0xa94133eb, 0xa8c52be9, 0x79400ea8, 0x14000000,
    0x7f41e3bf, 0x1e453d08, 0xfd75c925, 0xb7299d38, 0x84222325, 0xcbf29ce4,
    0x000001b3, 0x00000100, 0x54594c46, 0xa9be43ef, 0xa9017bf1, 0xd2800411,
    0x94000015, 0xa9417bf1, 0xa8c243ef, 0xd102c3ff, 0x14000000, 0xa9bd3fee,
    0xa90147f0, 0xa9027bed, 0xd53b420d, 0xf940000e, 0x90000010, 0x91000210,
    0xeb1001df, 0x54000061, 0xd2800511, 0x94000006, 0xd51b420d, 0xa9427bed,
    0xa94147f0, 0xa8c33fee, 0xd65f03c0, 0x9000000f, 0x910001ef, 0xf9400df0,
    0xb40000b0, 0xc8dffe10, 0x91000610, 0x8b1101ef, 0xc89ffdf0, 0xd65f03c0,
    0xf9400df0, 0x2a1f03e8, 0xb4000130, 0xc8dffe10, 0x91000610, 0xf94011f1,
    0xb40000b1, 0xcb110211, 0xf1000a3f, 0x54000048, 0x52800028, 0xd65f03c0,
    0xa9bf7be0, 0x91004000, 0x94000003, 0xa8c17be0, 0xd65f03c0, 0xa9bf7bef,
    0x9000000f, 0x910001ef, 0xb9400df0, 0x34000530, 0xb9403c10, 0x350004f0,
    0xb9403810, 0x52b7f00e, 0x6b0e021f, 0x54000461, 0xb9402810, 0x18ffdb6e,
    0x6b0e021f, 0x540003e1, 0xb9402c10, 0x18ffdb0e, 0x6b0e021f, 0x54000361,
    0xb9400810, 0xb940180e, 0x2a0e0210, 0x350002f0, 0xbd400000, 0x1cffd9c1,
    0x1e213801, 0x1e20c021, 0x1cffef42, 0x1e222020, 0x54000208, 0x1cffee81,
    0xb94009f0, 0x34000050, 0x1e270201, 0x1e210800, 0xbd001400, 0x1cffedc2,
    0x1e222020, 0x540000ea, 0x97ffffc8, 0x340000a8, 0x1e221821, 0x1e2e1002,
    0x1e213841, 0xbd001801, 0xa8c17bef, 0xd65f03c0, 0x2d411905, 0xa9be3fee,
    0xa90147f0, 0xadbe9fe0, 0x3d800bf0, 0xd53b4211, 0x9000000f, 0x910001ef,
    0xb9400df0, 0x340002d0, 0xb9404e70, 0x35000290, 0xbd401267, 0xbd402670,
    0x1e271a10, 0x1cffea87, 0x1e271a10, 0x1e2e1007, 0x1e3038f0, 0xbd402a67,
    0x1e2020e8, 0x5400014d, 0x1e3038e0, 0x1e20c000, 0x1cffe9d0, 0x1e302000,
    0x540000a8, 0x1e2c1010, 0x1e2608e7, 0x1e3008e7, 0x1e273842, 0xd51b4211,
    0x3dc00bf0, 0xacc19fe0, 0xa94147f0, 0xa8c23fee, 0x14000000, 0xa9bf7be1,
    0x94000000, 0xf94003e2, 0xaa1303e0, 0xaa1403e1, 0x94000004, 0xf94007fe,
    0x910043ff, 0xd65f03c0, 0x9000000f, 0x910001ef, 0xb9400df0, 0x34000cf0,
    0xb94009f0, 0x34000cb0, 0xf9405810, 0x9257fa10, 0x58000c8e, 0xeb0e021f,
    0x54000e00, 0x58000c6e, 0xeb0e021f, 0x54000da0, 0x39416c10, 0x12000e10,
    0x35000b50, 0xb940b010, 0x1800140e, 0x6b0e021f, 0x54000200, 0x180013ce,
    0x6b0e021f, 0x540001a0, 0x1800138e, 0x6b0e021f, 0x54000140, 0x1800134e,
    0x6b0e021f, 0x540000e0, 0x1800130e, 0x6b0e021f, 0x54000080, 0x180012ce,
    0x6b0e021f, 0x540008e1, 0x2a1f03eb, 0x2d4a0400, 0xf9406030, 0xb4000870,
    0x2d450e02, 0x1e222000, 0x54000801, 0x1e232020, 0x540007c1, 0xb9404c30,
    0x35000790, 0xbd402422, 0xbd401023, 0x1e231842, 0x1cffe063, 0x1e231842,
    0x1e202048, 0x540006ad, 0x1e2e1003, 0x1e232040, 0x5400064a, 0x1e221863,
    0x1e230824, 0xbd021444, 0x1e2c1005, 0x1e213884, 0x1e250884, 0xbd402826,
    0x1e2108c6, 0x1e2308c6, 0x1f0510c4, 0xbd421c45, 0x1e252884, 0xbd021c44,
    0x3500048b, 0xd2801c90, 0x5280006e, 0xd280310d, 0x3943c40c, 0x38ed6831,
    0x6b0c023f, 0x54000322, 0xbc706840, 0x91008211, 0xbc716841, 0x1e203821,
    0x1e2c1002, 0x1e204064, 0x1e2e1005, 0x1e253884, 0x1e220884, 0x1e210884,
    0x1e243800, 0xbc306840, 0x91004211, 0xbc716840, 0x1e243800, 0xbc316840,
    0x91008211, 0xbc716840, 0x1e242800, 0xbc316840, 0x9100c211, 0xbc716840,
    0x1e242800, 0xbc316840, 0x910005ad, 0x91010210, 0x710005ce, 0x54fffc41,
    0xd65f03c0, 0xd503201f, 0x5f4c5f50, 0x00003030, 0x5f525f50, 0x00003030,
    0x69435f50, 0x656c6372, 0x6e495f4e, 0x5f74754f, 0x746f6f52, 0x656e6150,
    0x44f00000, 0x44870000, 0x41f00000, 0x41f00000, 0xf9400c11, 0xb4fffdf1,
    0xf9405a30, 0x58fffe6e, 0xeb0e021f, 0x54fffd61, 0xb940ba30, 0x3942d40d,
    0x53103dad, 0x52860bee, 0x2a0d01ce, 0x6b0e021f, 0x54fffc81, 0xf9400e31,
    0xb4fffc51, 0xf9405a30, 0x58fffd0e, 0xeb0e021f, 0x54fffbc1, 0xb940ba30,
    0x3942d40d, 0x53185dad, 0x5280060e, 0x2a0d01ce, 0x6b0e021f, 0x54fffae1,
    0xf9402a30, 0x58fffc6e, 0xeb0e021f, 0x54fffa61, 0xf9400e31, 0xb4fffa31,
    0xf9405a30, 0x58fffb2e, 0xeb0e021f, 0x54fff9a1, 0x3942e230, 0x35fff970,
    0xf9402a30, 0x58fffaae, 0xeb0e021f, 0x54fff8e1, 0xf9406031, 0xb4fff8b1,
    0xf9401630, 0xeb0e021f, 0x54fff841, 0xbd405401, 0xbd402e22, 0x1e222020,
    0x54fff7c1, 0xbd421442, 0x1e222020, 0x54fff761, 0x5280002b, 0x17ffff7c,
    0x47425f50, 0x67425f50, 0x6f445f50, 0x6f435f50, 0x6c415f50, 0x74535f50,
    0x2a1f03e8, 0xf940580e, 0x58000b4f, 0xeb0f01df, 0x54000421, 0xb940b80e,
    0x5286060f, 0x6b0f01df, 0x540003a1, 0xf940280e, 0x58000acf, 0xeb0f01df,
    0x54000321, 0xf9400c11, 0xb40002f1, 0xf9402a2e, 0x58000a4f, 0xeb0f01df,
    0x54000261, 0xf9401411, 0x9100800e, 0xeb0e023f, 0x540001e0, 0xb40001d1,
    0xd1002231, 0xf9405a2e, 0x5800088f, 0xeb0f01df, 0x54000121, 0xb940ba2e,
    0x5286060f, 0x6b0f01df, 0x540000a1, 0xf9402a2e, 0x5800084f, 0xeb0f01df,
    0x1a9f17e8, 0xd65f03c0, 0xa9bd7be8, 0xa9013fee, 0xa90247f0, 0xd53b4210,
    0x9000000f, 0x910001ef, 0xb9400df1, 0x34000091, 0x97ffffd2, 0x34000048,
    0x32000063, 0xd51b4210, 0xa94247f0, 0xa9413fee, 0xa8c37be8, 0xfc1b0fe8,
    0x14000000, 0xa9bc7be8, 0xa9013fee, 0xa90247f0, 0xf9001bed, 0xadbf07e0,
    0xd53b420d, 0x9000000f, 0x910001ef, 0xb9400df1, 0x34000291, 0x97ffffbf,
    0x34000248, 0x9000000f, 0x910001ef, 0xb9400df0, 0x340001d0, 0xb94009f0,
    0x34000190, 0x1cffc680, 0x1e270201, 0x1e202020, 0x5400010a, 0x97fffe8d,
    0x350000c8, 0x1e211800, 0x1e2e1001, 0x1e213800, 0x1c000281, 0x1f018c03,
    0xd51b420d, 0xacc107e0, 0xf9401bed, 0xa94247f0, 0xa9413fee, 0xa8c47be8,
    0x53067d4a, 0x14000000, 0x6e495f4e, 0x5f74754f, 0x6c415f4e, 0x5f6e6769,
    0x41f00000, 0x41f00000, 0x44f00000, 0x44870000, 0x44e24000, 0x42c80000,
    0x44070000,
]
symbols = {'_dm_view_area': 760, '_dm_view_backdrop': 1904, '_dm_view_backdrop_call': 1868, '_dm_view_cache': 64, '_dm_view_capture': 536, '_dm_view_create': 652, '_dm_view_footer_match': 2640, '_dm_view_footer_recalc': 2792, '_dm_view_footer_y': 2860, '_dm_view_keyboard_frame': 1332, '_dm_view_layout': 1108, '_dm_view_matrix': 0, '_dm_view_near_xy': 960, '_dm_view_near_y': 900, '_dm_view_panel_projection': 1532, '_dm_view_scissor': 416, '_dm_view_scissor_origin': 1720, '_dm_view_sphere': 1020, '_dm_view_touch_page': 1364, '_dm_view_ui_override': 220, '_dm_view_ui_projection': 1512, '_dm_view_units': 864}
relocations = [(4, 3, '_dm_view_state'), (8, 4, '_dm_view_state'), (60, 2, '_dm_return_037e5978'), (72, 3, '_dm_view_state'), (76, 4, '_dm_view_state'), (108, 3, '_dm_code_04a65608'), (112, 4, '_dm_code_04a65608'), (140, 3, '_dm_view_state'), (144, 4, '_dm_view_state'), (224, 3, '_dm_view_state'), (228, 4, '_dm_view_state'), (428, 3, '_dm_view_state'), (432, 4, '_dm_view_state'), (532, 2, '_dm_return_03a308f0'), (544, 3, '_dm_view_state'), (548, 4, '_dm_view_state'), (648, 2, '_dm_return_03a2eac0'), (656, 3, '_dm_view_state'), (660, 4, '_dm_view_state'), (756, 2, '_dm_return_013a29a8'), (768, 3, '_dm_view_state'), (772, 4, '_dm_view_state'), (872, 3, '_dm_view_state'), (876, 4, '_dm_view_state'), (896, 2, '_dm_return_01462bb8'), (904, 3, '_dm_view_state'), (908, 4, '_dm_view_state'), (956, 2, '_dm_return_037e5a50'), (964, 3, '_dm_view_state'), (968, 4, '_dm_view_state'), (1016, 2, '_dm_return_037e5a80'), (1024, 3, '_dm_view_state'), (1028, 4, '_dm_view_state'), (1088, 2, '_dm_return_013a37c8'), (1132, 3, '_dm_view_state'), (1136, 4, '_dm_view_state'), (1292, 2, '_dm_return_00268ee4'), (1360, 2, '_dm_return_03268180'), (1384, 3, '_dm_code_049adc80'), (1388, 4, '_dm_code_049adc80'), (1428, 3, '_dm_view_state'), (1432, 4, '_dm_view_state'), (1536, 3, '_dm_view_state'), (1540, 4, '_dm_view_state'), (1744, 3, '_dm_view_state'), (1748, 4, '_dm_view_state'), (1864, 2, '_dm_return_03a30988'), (1872, 2, '_dm_code_00264a10'), (1904, 3, '_dm_view_state'), (1908, 4, '_dm_view_state'), (2808, 3, '_dm_view_state'), (2812, 4, '_dm_view_state'), (2856, 2, '_dm_return_0027d4c4'), (2884, 3, '_dm_view_state'), (2888, 4, '_dm_view_state'), (2908, 3, '_dm_view_state'), (2912, 4, '_dm_view_state'), (3004, 2, '_dm_return_0027d7c0')]
# END GENERATED VIEW CODE

def view(ctx):
    source=Path(__file__).with_name("view.s")
    assert hashlib.sha256(source.read_bytes()).hexdigest()==source_sha256, "regenerate view stubs after editing view.s"
    # PerspectiveProjection vtable lives in relocated data, outside read-only data.
    ctx.site(0x4a65660,"68597e0300000000")
    ctx.state=0x4724200
    ctx.site(ctx.state,"00"*64)
    # The native keyboard and drawing widgets retain fixed screen hit rectangles.
    header=struct.unpack("<16I",b"DMVIEW01"+bytes(12)+struct.pack("<f",16/9)+bytes(40))
    ctx.put(ctx.state,header,"adaptive-view state in verified unused image padding")
    start=ctx.here()
    for word in relocated_words(words,relocations,symbols,start,ctx.state):ctx.emit(word)
    hooks=[
        (0x27d4c0,"e80f1bfc","_dm_view_footer_recalc",False),
        (0x27d7bc,"4a7d0653","_dm_view_footer_y",False),
        (0x326817c,"ffc302d1","_dm_view_keyboard_frame",False),
        (0x2af1258,"c0035fd6","_dm_view_touch_page",False),
        (0x265140,"c0035fd6","_dm_view_ui_projection",False),
        (0x3a30984,"0519412d","_dm_view_scissor_origin",False),
        (0x284048,"7282ff97","_dm_view_backdrop_call",True),
        (0x2840e4,"4b82ff97","_dm_view_backdrop_call",True),
        (0x268ee0,"a80e4079","_dm_view_layout",False),
        (0x5ce924,"00210091","_dm_view_ui_override",False),
        (0x37e5974,"0188552d","_dm_view_matrix",False),
        (0x3a308e8,"0318221e2218241e","_dm_view_scissor",False),
        (0x3a2eabc,"2219221e","_dm_view_capture",False),
        (0x13a29a4,"4039291e","_dm_view_create",False),
        (0x1126144,"800240bd","_dm_view_area",True),
        (0x1125fe4,"800240bd","_dm_view_area",True),
        (0x1462bb4,"080040b9","_dm_view_units",False),
        (0x37e5a4c,"01ac40bd","_dm_view_near_y",False),
        (0x37e5a7c,"028c552d","_dm_view_near_xy",False),
        (0x13a37b4,"0020211e00cc211ea021201ea0cd201e0008291e","_dm_view_sphere",False),
    ]
    for site,original,symbol,link in hooks:
        ctx.site(site,original)
        branch=B(site,start+symbols[symbol])|(0x80000000 if link else 0)
        ctx.put(site,[branch],"adaptive-view "+symbol)
    # The compiler inlines the same cache check throughout game and UI code.
    # Each source register and load is asserted; the shared predicate additionally
    # verifies the actual projection class before changing the dirty result.
    caches=[
        (0x15083c,20,8,"88224039"),
        (0x2b8888,0,8,"08204039"),
        (0x5ce93c,19,8,"68224039"),
        (0x31c3074,20,8,"88224039"),
        (0x3268228,21,8,"a8224039"),
        (0x37b0eec,19,8,"68224039"),
        (0x37c1b0c,25,8,"28234039"),
        (0x37e5654,0,8,"08204039"),
        (0x38189d8,3,8,"68204039"),
        (0x3818a34,22,8,"c8224039"),
        (0x3818c70,24,8,"08234039"),
        (0x3819a08,24,8,"08234039"),
        (0x384225c,23,8,"e8224039"),
        (0x38423d8,23,8,"e8224039"),
        (0x386a888,21,8,"a8224039"),
        (0x3883a94,20,8,"88224039"),
        (0x389ebc0,21,8,"a8224039"),
        (0x3908dc8,19,8,"68224039"),
        (0x39af314,20,9,"89224039"),
        (0x39af334,20,9,"89224039"),
        (0x3a77ac4,27,8,"68234039"),
        (0x3a789d4,24,8,"08234039"),
        (0x3ab6100,21,8,"a8224039"),
        (0x3ab7190,24,8,"08234039"),
        (0x3abb650,21,8,"a8224039"),
        (0x3abc700,24,8,"08234039"),
        (0x3b2235c,26,8,"48234039"),
        (0x3b55694,20,8,"88224039"),
        (0x3db2bf0,27,8,"68234039"),
    ]
    for site,source,destination,original in caches:
        ctx.site(site,original);body=ctx.here()
        ctx.emit(STP_PRE(0,30,31,-16));ctx.emit(STP_PRE(8,9,31,-16));ctx.emit(STP_PRE(15,16,31,-16))
        ctx.emit(0xaa0003e0|(source<<16))  # mov x0,xSource
        ctx.emit(B(ctx.here(),start+symbols["_dm_view_cache"])|0x80000000)
        ctx.emit(STRX(8,31,2 if destination==8 else 3))
        ctx.emit(LDP_POST(15,16,31,16));ctx.emit(LDP_POST(8,9,31,16));ctx.emit(LDP_POST(0,30,31,16))
        ctx.emit(B(ctx.here(),site+4))
        ctx.put(site,[B(site,body)],"refresh cached projection after a view target change")

VIEW={"ff1d1c05670db6021c85b624a710b963":view}
