import Foundation
@main struct TouchControlsCheck {
    static func main() throws {
        let suite="touch-profile-test-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        var portrait=TouchControlProfile();portrait.offsets["face"]=TouchControlOffset(x:0.12,y:-0.08);portrait.scale=1.2;portrait.deadZone=0.18;portrait.save(true,defaults:defaults)
        assert(TouchControlProfile.load(true,defaults:defaults)==portrait)
        assert(TouchControlProfile.load(false,defaults:defaults)==TouchControlProfile())
        var landscape=TouchControlProfile();landscape.opacity=0.5;landscape.offsets["leftStick"]=TouchControlOffset(x:0.2,y:0.1);landscape.save(false,defaults:defaults)
        assert(TouchControlProfile.load(true,defaults:defaults)==portrait && TouchControlProfile.load(false,defaults:defaults)==landscape)
        var invalid=TouchControlProfile();invalid.scale = .infinity;invalid.opacity = -1;invalid.deadZone=2;invalid.offsets=["face":TouchControlOffset(x:.nan,y:4),"unknown":TouchControlOffset(x:0,y:0)];invalid.validate()
        assert(invalid.scale==1 && invalid.opacity==0.25 && invalid.deadZone==0.3 && invalid.offsets["face"]==TouchControlOffset(x:0,y:0.75) && invalid.offsets["unknown"]==nil)
        defaults.set(Data("invalid JSON".utf8),forKey:"DmTouchPortraitV1");assert(TouchControlProfile.load(true,defaults:defaults)==TouchControlProfile())
        print("Touch profiles: independent orientations, persistence, finite geometry, range validation and corrupt-setting recovery PASS")
    }
}
