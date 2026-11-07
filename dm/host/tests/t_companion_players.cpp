// Exercise the actual pinned reader on synthetic multiplayer actor lists.
#include "../../third_party/eden_duo/acnh/acnh_live.cpp"
#include "../../third_party/eden_duo/acnh/acnh_live_extra.cpp"
#include <cassert>
#include <iostream>

struct Memory {
    static constexpr uint64_t main_base = 0x7100000000, heap_base = 0x100000000;
    std::vector<uint8_t> main = std::vector<uint8_t>(0x6000000);
    std::vector<uint8_t> heap = std::vector<uint8_t>(0x1800000);
    uint8_t *range(uint64_t at, size_t n) {
        for (auto [base, bytes] : {std::pair{main_base, &main}, std::pair{heap_base, &heap}})
            if (at >= base && n <= bytes->size() && at-base <= bytes->size()-n)
                return bytes->data()+at-base;
        return nullptr;
    }
    template<class T> void put(uint64_t at, T value) {
        auto *out = range(at, sizeof value); assert(out); std::memcpy(out, &value, sizeof value);
    }
    static EdenDsmodBool read(void *p, uint64_t at, void *out, size_t n) {
        auto *value = static_cast<Memory *>(p)->range(at,n);
        if (!value) return 0;
        std::memcpy(out,value,n); return 1;
    }
};

int main() {
    using namespace acnh::live;
    Memory memory;
    EdenDsmodHostApi host{};
    host.userdata = &memory; host.main_base = Memory::main_base;
    host.main_size = memory.main.size(); host.read_memory = Memory::read;
    Guest guest(host); Reader reader;
    for (auto *pin : AllPins)
        for (size_t i=0; i<pin->words.size(); ++i)
            memory.put(host.main_base+pin->offset+i*4, pin->words[i]);
    std::string why; assert(reader.Resolve(guest,why));
    const uint64_t manager = Memory::heap_base+0x1000;
    const uint64_t vtable = Memory::main_base+0x1000;
    const uint64_t list_vtable = acnh::PinData(guest,PinActorListComp,0,1);
    const uint64_t components[2] = {Memory::heap_base+0x10000, Memory::heap_base+0x11000};
    const uint64_t actors[2] = {Memory::heap_base+0x20000, Memory::heap_base+0x23000};
    memory.put(reader.roots.actor_list,manager);
    memory.put(manager+0x10,components[0]+0x290);
    memory.put<int32_t>(manager+0x20,2); memory.put<int32_t>(manager+0x24,0);
    memory.put(vtable+0x10,reader.roots.player_actor_name);
    for (int i=0; i<2; ++i) {
        memory.put(components[i],list_vtable);
        memory.put(components[i]+0x278,components[i]+0x290);
        memory.put(components[i]+0x48,actors[i]);
        memory.put(components[i]+0x290,i ? manager+0x10 : components[1]+0x290);
        memory.put(actors[i],vtable); memory.put<uint8_t>(actors[i]+0x1ee8,i);
    }
    Need need{}; LiveSnapshot snapshot{};
    memory.put<int32_t>(manager+0x20,1);
    memory.put(components[0]+0x290,manager+0x10);
    memory.put<uint8_t>(reader.roots.pno_override,0);
    reader.Sample(guest,need,snapshot); assert(snapshot.actor_at==actors[0]);
    memory.put<int32_t>(manager+0x20,2);
    memory.put(components[0]+0x290,components[1]+0x290);
    for (int local=0; local<2; ++local) {
        memory.put<uint8_t>(reader.roots.pno_override,local);
        reader.Sample(guest,need,snapshot);
        assert(snapshot.player_no==local && snapshot.actor_at==actors[local]);
    }
    // List order must not determine the local actor, and ambiguous identity fails closed.
    memory.put(manager+0x10,components[1]+0x290);
    memory.put(components[1]+0x290,components[0]+0x290);
    memory.put(components[0]+0x290,manager+0x10);
    reader.Sample(guest,need,snapshot); assert(snapshot.actor_at==actors[1]);
    memory.put<uint8_t>(actors[0]+0x1ee8,1);
    reader.Sample(guest,need,snapshot); assert(!snapshot.actor_at);
    memory.put<uint8_t>(actors[0]+0x1ee8,0);
    memory.put<uint8_t>(reader.roots.pno_override,2);
    reader.Sample(guest,need,snapshot); assert(!snapshot.actor_at);
    // A visitor's alternate object contains Land without GSaveMain's prefix.
    const uint64_t mgr=Memory::heap_base+0x3000, set=Memory::heap_base+0x4000;
    const uint64_t home=Memory::heap_base+0x5000, visit=Memory::heap_base+0x5100;
    const uint64_t home_tree=Memory::heap_base+0x6000, visit_tree=Memory::heap_base+0x6100;
    const uint64_t personal=Memory::heap_base+0x7000, personal_data=Memory::heap_base+0x1100000;
    const uint64_t home_data=Memory::heap_base+0x100000, visit_data=Memory::heap_base+0xb00000;
    const uint64_t home_vt=Memory::main_base+0x2000, visit_vt=Memory::main_base+0x2100;
    const uint64_t player_map=Memory::heap_base+0x8000, player_got=Memory::heap_base+0x8100;
    const uint64_t player_records=Memory::heap_base+0x9000;
    memory.put(reader.roots.visit_player_map,player_map);
    memory.put(reader.roots.visit_player_records,player_got); memory.put(player_got,player_records);
    memory.put<int32_t>(player_map,0); memory.put<int32_t>(player_map+4,0);
    memory.put<uint32_t>(player_records+0x13d0,0);
    memory.put<uint8_t>(player_records+0x13d4,1); memory.put<uint8_t>(player_records+0x13d5,0);
    memory.put(reader.roots.save_mgr,mgr); memory.put(mgr+0x10,set);
    memory.put<uint32_t>(mgr+0x90,0); memory.put<uint32_t>(mgr+0x94,1);
    memory.put(set,home); memory.put(set+0x130,visit); memory.put(set+0x60,personal);
    memory.put(personal+0x10,personal_data);
    memory.put(home,home_vt); memory.put(home+0x10,home_data);
    memory.put(home+0x18,home_data+M::Size+0x20); memory.put(home+0x20,home_tree);
    memory.put(home_vt+0x10,reader.roots.save_vt_slot2); memory.put(home_vt+0x38,reader.roots.save_vt_slot7);
    memory.put(home_tree+0x78,home_data); memory.put<uint64_t>(home_tree+0x80,M::Land);
    memory.put<uint32_t>(home_data,0xa0002); memory.put<uint32_t>(home_data+4,0xa0028);
    memory.put(visit,visit_vt); memory.put(visit+0x10,visit_data);
    memory.put(visit+0x18,visit_data+0x5b3c60); memory.put(visit+0x20,visit_tree);
    memory.put(visit_vt+0x10,reader.roots.visit_save_slot2); memory.put(visit_vt+0x38,reader.roots.visit_save_slot7);
    memory.put(visit_tree+0x78,visit_data); memory.put<uint64_t>(visit_tree+0x80,0);
    memory.put<uint32_t>(visit_data,0x12345678); // Land has no GSaveMain version header.
    const std::array<char16_t,10> home_name={u'H',u'o',u'm',u'e'}, visit_name={u'V',u'i',u's',u'i',u't'};
    memory.put(home_data+M::IslandName,home_name); memory.put(visit_data+M::IslandName-M::Land,visit_name);
    memory.put<uint8_t>(home_data+M::LandMaking,0x11); memory.put<uint8_t>(visit_data+M::LandMaking-M::Land,0x22);
    memory.put<uint8_t>(reader.roots.pno_override,0); memory.put<uint8_t>(mgr+0x453,0);
    reader.Sample(guest,need,snapshot);
    assert(snapshot.save_ok && snapshot.personal_ok && snapshot.island_name==u"Home" && snapshot.land_making[0]==0x11);
    memory.put<uint8_t>(mgr+0x453,1); reader.Sample(guest,need,snapshot);
    assert(snapshot.save_ok && snapshot.personal_ok && snapshot.island_name==u"Visit" && snapshot.land_making[0]==0x22);
    assert(snapshot.land_offset==M::Land && snapshot.main_dat==visit_data && snapshot.island_tree==visit_tree);
    memory.put<uint8_t>(reader.roots.pno_override,1);
    reader.Sample(guest,need,snapshot);
    assert(snapshot.player_no==1 && snapshot.personal_ok && snapshot.personal_at==personal_data);
    // A different home-resident id and loaded slot must not be confused with
    // either the actor number or the network map's record index.
    memory.put<uint32_t>(mgr+0x90,5); memory.put<uint8_t>(player_records+0x13d5,5);
    reader.Sample(guest,need,snapshot); assert(snapshot.personal_ok && snapshot.personal_slot==0);
    memory.put<uint32_t>(mgr+0x94,0); memory.put<uint32_t>(mgr+0xa8,5); memory.put<uint32_t>(mgr+0xac,1);
    memory.put(set+0x60+3*8,personal);
    reader.Sample(guest,need,snapshot); assert(snapshot.personal_ok && snapshot.personal_slot==3);
    memory.put<uint32_t>(player_records+0x13d0,1);
    reader.Sample(guest,need,snapshot); assert(!snapshot.personal_ok && !snapshot.personal_at);
    memory.put<uint32_t>(player_records+0x13d0,0); memory.put<uint8_t>(player_records+0x13d4,0);
    reader.Sample(guest,need,snapshot); assert(!snapshot.personal_ok);
    memory.put<uint8_t>(player_records+0x13d4,1); memory.put<int32_t>(player_map+4,-1);
    reader.Sample(guest,need,snapshot); assert(!snapshot.personal_ok);
    memory.put<int32_t>(player_map+4,8);
    reader.Sample(guest,need,snapshot); assert(!snapshot.personal_ok);
    memory.put<int32_t>(player_map+4,0);
    reader.Sample(guest,need,snapshot); assert(snapshot.personal_ok);
    assert(!snapshot.IslandField(0x10) && !snapshot.IslandField(M::Land+0x5b3c5f,2));
    ExtraReader extra; ExtraSnapshot extra_snapshot; ExtraReader::Need extra_need{}; extra_need.map=true;
    extra.Sample(guest,snapshot,extra_need,extra_snapshot); assert(extra_snapshot.houses_ok);
    memory.put(visit_vt+0x38,reader.roots.save_vt_slot7);
    reader.Sample(guest,need,snapshot); assert(!snapshot.save_ok); // No mixed accessor pair.
    memory.put(visit_vt+0x38,reader.roots.visit_save_slot7); memory.put<uint64_t>(visit_tree+0x80,M::Land);
    reader.Sample(guest,need,snapshot); assert(!snapshot.save_ok); // No guessed origin.
    memory.put<uint64_t>(visit_tree+0x80,0); memory.put(visit+0x18,visit_data+0x100);
    reader.Sample(guest,need,snapshot); assert(!snapshot.save_ok); // No truncated buffer.
    memory.put(visit+0x18,visit_data+0x5b3c60);
    memory.put<uint32_t>(host.main_base+PinVisitSaveData.offset,0);
    Reader bad_visit; bad_visit.Sample(guest,need,snapshot); assert(!snapshot.save_ok);
    memory.put<uint32_t>(host.main_base+PinVisitSaveData.offset,PinVisitSaveData.words[0]);
    memory.put<uint32_t>(host.main_base+PinVisitPersonal.offset,0);
    Reader bad_personal; bad_personal.Sample(guest,need,snapshot); assert(snapshot.save_ok && !snapshot.personal_ok);
    memory.put<uint8_t>(reader.roots.pno_override,5);
    memory.put<uint8_t>(mgr+0x453,0); bad_personal.Sample(guest,need,snapshot); assert(snapshot.personal_ok);
    memory.put<uint8_t>(mgr+0x453,0); bad_visit.Sample(guest,need,snapshot); assert(snapshot.save_ok);
    memory.put<uint32_t>(home_data,0); bad_visit.Sample(guest,need,snapshot); assert(!snapshot.save_ok);
    std::cout << "Companion island buffers: full/visitor origins, personal data, terrain, house map, bounds, schema and pins PASS\n";
    std::cout << "Companion visiting personal: network/resident/slot remapping, record validity, kind and pin rejection PASS\n";
    memory.put<uint8_t>(reader.roots.pno_override,1);
    memory.put<uint32_t>(host.main_base+PinPlayerActorNo.offset,0);
    Reader unsupported; unsupported.Sample(guest,need,snapshot); assert(!snapshot.actor_at);
    std::cout << "Companion local actor: solo, host, visitor, reversed order, duplicate/absent identity and mismatched code pin PASS\n";
}
