// Appended to the renderer in this test target so production privacy stays intact.
extension EdenImages {
    func discardWarmImagesForTest(){cache.removeAllObjects()}
    func seedFailureForTest(_ key:String,_ attempts:Int,_ age:TimeInterval){failed[key]=Date().addingTimeInterval(-age);self.attempts[key]=attempts}
    var retryDelayForTest:Double?{retryAt?.timeIntervalSinceNow}
    var failureCountForTest:Int{failed.count}
}
@main struct EdenImagesCheck {
    @MainActor static func settle() async {for _ in 0..<8{await Task.yield()};try? await Task.sleep(for:.milliseconds(10))}
    @MainActor static func main() async {
        var loads=0
        var delayed:((Data?,Int,Int)->Void)?
        let pixels=Data([255,0,0,255])
        let model=CompanionModel(reader:{["acnh.ready":1]},sender:{_,_ in},images:{key,done in
            loads+=1
            if key=="module:delayed"{delayed=done}
            else if key.hasPrefix("module:bad") || key=="module:fast"{done(nil,0,0)}
            else{done(pixels,1,1)}
        })
        let images=EdenImages()
        images.request(["module:first"],model);await settle()
        assert(images.get("module:first") != nil)
        assert(images.get("module:first")?.colorSpace?.name == CGColorSpace.sRGB)
        // Warm colours and teal app icons retain their authored values when
        // composited into either sRGB or a wide-gamut display surface.
        let palette=Data([52,174,132,255,231,143,53,255,136,71,229,255])
        let paletteModel=CompanionModel(reader:{["acnh.ready":1]},sender:{_,_ in},images:{_,done in done(palette,3,1)})
        let paletteImages=EdenImages();paletteImages.request(["module:palette"],paletteModel);await settle()
        let source=paletteImages.get("module:palette")!
        assert(source.colorSpace?.name == CGColorSpace.sRGB)
        for name in [CGColorSpace.sRGB,CGColorSpace.displayP3] {
            let surface=CGContext(data:nil,width:3,height:1,bitsPerComponent:8,bytesPerRow:12,space:CGColorSpace(name:name)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            surface.draw(source,in:CGRect(x:0,y:0,width:3,height:1))
            let roundtrip=CGContext(data:nil,width:3,height:1,bitsPerComponent:8,bytesPerRow:12,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            roundtrip.draw(surface.makeImage()!,in:CGRect(x:0,y:0,width:3,height:1))
            let actual=roundtrip.data!.assumingMemoryBound(to:UInt8.self)
            for i in 0..<palette.count {assert(abs(Int(actual[i])-Int(palette[i]))<=2)}
        }
        images.discardWarmImagesForTest()
        assert(images.get("module:first") != nil)
        let loaded=loads
        images.request(["module:first"],model);await settle();assert(loads==loaded)
        images.request(["module:second"],model);await settle();images.discardWarmImagesForTest()
        assert(images.get("module:first")==nil && images.get("module:second") != nil)
        model.visible(false);images.suspend();images.discardWarmImagesForTest()
        assert(images.get("module:second")==nil)
        model.visible(true);images.request(["module:second"],model);await settle()
        let beforeTrim=loads
        images.trim();assert(images.get("module:second")==nil)
        images.request(["module:second"],model);await settle()
        assert(loads==beforeTrim+1 && images.get("module:second") != nil)
        images.request(["module:delayed"],model)
        images.request(["module:second"],model)
        delayed?(pixels,1,1);delayed=nil;await settle();images.discardWarmImagesForTest()
        assert(images.get("module:delayed")==nil && images.get("module:second") != nil)
        var order:[String]=[]
        var completions:[String:(Data?,Int,Int)->Void]=[:]
        let slowModel=CompanionModel(reader:{["acnh.ready":1]},sender:{_,_ in},images:{key,done in
            order.append(key);completions[key]=done
        })
        let switching=EdenImages()
        switching.request((0..<40).map {"module:old\($0)"},slowModel)
        assert(order==["module:old0","module:old1"])
        switching.request(["module:wallpaper","module:tab","module:item"],slowModel)
        completions.removeValue(forKey:"module:old0")?(pixels,1,1);await settle()
        assert(order==["module:old0","module:old1","module:wallpaper"])
        completions.removeValue(forKey:"module:old1")?(pixels,1,1);await settle()
        assert(order.last=="module:tab" && switching.get("module:old1")==nil)
        completions.removeValue(forKey:"module:wallpaper")?(pixels,1,1);await settle()
        assert(order.last=="module:item" && switching.get("module:wallpaper") != nil)
        slowModel.visible(false);switching.suspend()
        completions.removeValue(forKey:"module:tab")?(pixels,1,1)
        completions.removeValue(forKey:"module:item")?(pixels,1,1);await settle()
        assert(switching.get("module:item")==nil)
        for i in 0..<32{images.request(["module:bad\(i)"],model);await settle();assert(images.failureCountForTest<=1)}
        images.trim();images.seedFailureForTest("module:slow",5,0)
        images.request(["module:slow","module:fast"],model);await settle()
        assert((images.retryDelayForTest ?? 99)>1 && (images.retryDelayForTest ?? 99)<3)
        // A cancelled earlier callback cannot erase a newly scheduled retry.
        images.trim();images.seedFailureForTest("module:old",5,29.95)
        images.request(["module:old"],model)
        images.trim();images.seedFailureForTest("module:new",1,0)
        images.request(["module:new"],model)
        try? await Task.sleep(for:.milliseconds(120))
        assert((images.retryDelayForTest ?? 0)>1)
        // An expired failure that is already loading needs no 50-ms polling loop.
        images.trim();images.seedFailureForTest("module:delayed",1,3)
        images.request(["module:delayed"],model)
        assert(images.retryDelayForTest==nil)
        delayed?(nil,0,0);delayed=nil;await settle()
        assert((images.retryDelayForTest ?? 0)>3)
        model.visible(false);images.suspend();assert(images.retryDelayForTest==nil)
        print("companion images: visible pins, eviction, hide, trim, stale completion, bounded failure scope and retry generations passed")
    }
}
