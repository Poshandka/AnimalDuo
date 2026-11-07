import Foundation
@main struct TouchControlsCheck {
    static func main() throws {
        let suite="touch-profile-test-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let legacyJSON = Data(#"{"scale":1.2,"opacity":0.8,"deadZone":0.18,"stickKnobScale":1.4,"offsets":{"face":{"x":0.12,"y":-0.08}}}"#.utf8)
        defaults.set(legacyJSON, forKey: "DmTouchPortraitV1")
        let legacy = TouchControlProfile.load(true, defaults: defaults)
        assert(legacy.scale == 1.2 && legacy.opacity == 0.8 && legacy.deadZone == 0.18)
        assert(legacy.offsets["face"] == TouchControlOffset(x: 0.12, y: -0.08))
        assert(legacy.slowWalkRadius == nil && legacy.dictionary["slowWalkRadius"] == nil)
        assert(legacy.dictionary["stickKnobScale"] == nil)

        var portrait = legacy
        portrait.slowWalkRadius = 0.60
        portrait.save(true, defaults: defaults)
        assert(TouchControlProfile.load(true,defaults:defaults)==portrait)
        assert(TouchControlProfile.load(false,defaults:defaults)==TouchControlProfile())
        var landscape = TouchControlProfile()
        landscape.opacity = 0.5
        landscape.offsets["leftStick"] = TouchControlOffset(x: 0.2, y: 0.1)
        landscape.slowWalkRadius = 0.31
        landscape.save(false, defaults: defaults)
        assert(TouchControlProfile.load(true,defaults:defaults)==portrait && TouchControlProfile.load(false,defaults:defaults)==landscape)
        var invalid=TouchControlProfile();invalid.scale = .infinity;invalid.opacity = -1;invalid.deadZone=2;invalid.offsets=["face":TouchControlOffset(x:.nan,y:4),"unknown":TouchControlOffset(x:0,y:0)];invalid.validate()
        assert(invalid.scale==1 && invalid.opacity==0.25 && invalid.deadZone==0.3 && invalid.offsets["face"]==TouchControlOffset(x:0,y:0.75) && invalid.offsets["unknown"]==nil)
        invalid.slowWalkRadius = 0.1
        invalid.validate()
        assert(invalid.slowWalkRadius == 0.35) // The dead zone was clamped to 30%.
        invalid.slowWalkRadius = 1
        invalid.validate()
        assert(invalid.dictionary["slowWalkRadius"] as? Double == 0.70)
        invalid.slowWalkRadius = .infinity
        invalid.validate()
        assert(invalid.slowWalkRadius == nil)
        defaults.set(Data("invalid JSON".utf8),forKey:"DmTouchPortraitV1");assert(TouchControlProfile.load(true,defaults:defaults)==TouchControlProfile())
        print("Touch profiles: independent orientations, persistence, finite geometry, range validation and corrupt-setting recovery PASS")
    }
}
