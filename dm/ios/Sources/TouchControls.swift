import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TouchControlOffset:Codable,Equatable { var x:Double=0;var y:Double=0 }
struct TouchControlProfile:Codable,Equatable {
    var scale:Double=1,opacity:Double=1,deadZone:Double=0.1
    var offsets:[String:TouchControlOffset]=[:]
    // A missing radius uses the original linear response.
    var slowWalkRadius: Double?
    var slowWalkRadiusRange: ClosedRange<Double> {
        max(0.20, deadZone + 0.05)...0.70
    }

    mutating func validate() {
        scale=scale.isFinite ? min(1.35,max(0.65,scale)):1
        opacity=opacity.isFinite ? min(1,max(0.25,opacity)):1
        deadZone=deadZone.isFinite ? min(0.3,max(0,deadZone)):0.1
        if let radius = slowWalkRadius {
            let range = slowWalkRadiusRange
            slowWalkRadius = radius.isFinite ? min(range.upperBound, max(range.lowerBound, radius)) : nil
        }
        offsets=offsets.filter{Self.groups.contains($0.key)}.mapValues { o in
            TouchControlOffset(x:o.x.isFinite ? min(0.75,max(-0.75,o.x)):0,y:o.y.isFinite ? min(0.75,max(-0.75,o.y)):0)
        }
    }
    static let groups=["leftStick","rightStick","face","dpad","shoulderL","shoulderR","clickL","clickR","minus","plus","layout"]
    var dictionary:[String:Any] {
        var values: [String: Any] = ["scale":scale,"opacity":opacity,"deadZone":deadZone,
                                    "offsets":offsets.mapValues{["x":$0.x,"y":$0.y]}]
        values["slowWalkRadius"] = slowWalkRadius
        return values
    }
    static func load(_ portrait:Bool,defaults:UserDefaults = .standard)->Self {
        guard let data=defaults.data(forKey:portrait ? "DmTouchPortraitV1":"DmTouchLandscapeV1"),var value=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        value.validate();return value
    }
    func save(_ portrait:Bool,defaults:UserDefaults = .standard) {
        var checked=self;checked.validate()
        if let data=try? JSONEncoder().encode(checked){defaults.set(data,forKey:portrait ? "DmTouchPortraitV1":"DmTouchLandscapeV1")}
        NotificationCenter.default.post(name:Notification.Name("DmTouchProfileChanged"),object:nil)
    }
}

#if os(iOS)
private struct TouchControlHandle:Identifiable {let id:String,title:String,x:Double,y:Double}
private struct TouchControlPreview:UIViewRepresentable {
    let portrait:Bool,profile:TouchControlProfile
    @Binding var handles:[TouchControlHandle]
    func makeUIView(context:Context)->UIView {dm_touch_controls_preview(portrait)}
    func updateUIView(_ view:UIView,context:Context) {
        dm_touch_controls_configure(view,profile.dictionary,portrait)
        DispatchQueue.main.async {
            view.layoutIfNeeded()
            let next=(dm_touch_controls_handles(view) as? [[String:Any]] ?? []).compactMap { row -> TouchControlHandle? in
                guard let id=row["id"] as? String,let title=row["title"] as? String,let x=row["x"] as? Double,let y=row["y"] as? Double else{return nil}
                return TouchControlHandle(id:id,title:title,x:x,y:y)
            }
            if next.map({"\($0.id):\($0.x):\($0.y)"}) != handles.map({"\($0.id):\($0.x):\($0.y)"}){handles=next}
        }
    }
}
struct TouchControlsEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State private var portrait=DMCompanion.shared().supported
    @State private var portraitProfile=TouchControlProfile.load(true)
    @State private var landscapeProfile=TouchControlProfile.load(false)
    @State private var handles:[TouchControlHandle]=[]
    @State private var dragOrigins:[String:TouchControlOffset]=[:]
    private var profile:Binding<TouchControlProfile> {portrait ? $portraitProfile:$landscapeProfile}
    private var walkRadius: Binding<Double> {
        Binding {
            let current = profile.wrappedValue
            return current.slowWalkRadius ?? dm_touch_default_slow_walk_radius(current.deadZone)
        } set: { value in
            profile.wrappedValue.slowWalkRadius = value
            profile.wrappedValue.validate()
        }
    }
    private var deadZone: Binding<Double> {
        Binding {
            profile.wrappedValue.deadZone
        } set: { value in
            profile.wrappedValue.deadZone = value
            profile.wrappedValue.validate()
        }
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:16) {
                    Picker(companionText("Layout"),selection:$portrait){
                        Text(companionText("Landscape")).tag(false)
                        if DMCompanion.shared().supported{Text(companionText("Portrait controls")).tag(true)}
                    }.pickerStyle(.segmented)
                    GeometryReader { geometry in
                        TouchControlPreview(portrait:portrait,profile:profile.wrappedValue,handles:$handles)
                            .allowsHitTesting(false)
                        ForEach(handles){h in
                            Text(h.title).font(.caption.bold()).padding(7).background(.ultraThinMaterial,in:Capsule())
                                .position(x:h.x*geometry.size.width,y:h.y*geometry.size.height)
                                .gesture(DragGesture(minimumDistance:1).onChanged{g in
                                    if dragOrigins[h.id]==nil{dragOrigins[h.id]=profile.wrappedValue.offsets[h.id] ?? TouchControlOffset()}
                                    let original=dragOrigins[h.id]!
                                    profile.wrappedValue.offsets[h.id]=TouchControlOffset(x:original.x+g.translation.width/geometry.size.width,y:original.y+g.translation.height/geometry.size.height)
                                    profile.wrappedValue.validate()
                                }.onEnded{_ in dragOrigins.removeValue(forKey:h.id)})
                                .accessibilityIdentifier("controls.handle."+h.id)
                        }
                    }
                    .frame(height:portrait ? 440:300)
                    .background(Color(red:0.12,green:0.21,blue:0.19),in:RoundedRectangle(cornerRadius:16))
                    Text(companionText("Drag the labels to move control groups. Portrait excludes the bottom navigation bar."))
                        .font(.footnote).foregroundStyle(.secondary)
                    slider("Button size",profile.scale,0.65...1.35)
                    slider("Button opacity",profile.opacity,0.25...1)
                    slowWalkControl
                    slider("Stick dead zone",deadZone,0...0.3)
                    Button(companionText("Reset this layout")){profile.wrappedValue=TouchControlProfile();dragOrigins=[:]}
                }.padding()
            }
            .navigationTitle(companionText("Touch controls"))
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button(companionText("Cancel")){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(companionText("Save")){portraitProfile.save(true);landscapeProfile.save(false);dismiss()}.accessibilityIdentifier("controls.save")}
            }
            .onChange(of:portrait){_ in handles=[];dragOrigins=[:]}
        }.presentationDetents([.large])
    }
    private var slowWalkControl: some View {
        let diameter = 56.0
        let zone = diameter * walkRadius.wrappedValue
        let dead = diameter * deadZone.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                    Circle().fill(Color.accentColor.opacity(0.55)).frame(width: zone, height: zone)
                    Circle().fill(.background).frame(width: dead, height: dead)
                }
                .frame(width: diameter, height: diameter)
                .accessibilityHidden(true)
                slider("Left stick slow-walk zone", walkRadius, profile.wrappedValue.slowWalkRadiusRange)
            }
            Text(companionText("The percentage is relative to the outer ring radius. A larger zone lets you push farther before speeding up."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func slider(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
        VStack {
            HStack {
                Text(companionText(title))
                Spacer()
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(Text(companionText(title)))
        }
    }
}
#endif
