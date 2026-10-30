// Shared by the actual pad and its input-free layout preview.
- (double)customNumber:(NSString *)key fallback:(double)value low:(double)low high:(double)high {
    id n=_custom[key];double d=[n isKindOfClass:NSNumber.class] ? [n doubleValue] : value;
    return isfinite(d) ? fmin(high,fmax(low,d)) : value;
}
- (CGFloat)controlScale {return [self customNumber:@"scale" fallback:1 low:.65 high:1.35];}
- (BOOL)fixedRight {
    id offsets=_custom[@"offsets"];
    return _sideControls || _nativeSurface || ([offsets isKindOfClass:NSDictionary.class] && offsets[@"rightStick"]!=nil);
}
- (void)reloadProfile:(NSNotification *)note {
    (void)note;NSData *data=[NSUserDefaults.standardUserDefaults dataForKey:_sideControls ? @"DmTouchPortraitV1":@"DmTouchLandscapeV1"];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    _custom=[value isKindOfClass:NSDictionary.class] ? value : @{};
    if(!_previewMode)[self reset];[self applyLayout];[self updateArtwork];[self setNeedsLayout];
}
- (void)configureProfile:(NSDictionary *)profile portrait:(BOOL)portrait {
    if(!_previewMode)return;_sideControls=portrait;_custom=profile;[self applyLayout];[self updateArtwork];[self setNeedsLayout];
}
- (CGPoint)moved:(CGPoint)p group:(NSString *)group radius:(CGFloat)radius {
    id offsets=_custom[@"offsets"];id offset=[offsets isKindOfClass:NSDictionary.class] ? offsets[group] : nil;
    if(![offset isKindOfClass:NSDictionary.class]){if(self.controlScale==1)return p;offset=@{};}
    double x=[offset[@"x"]isKindOfClass:NSNumber.class] ? [offset[@"x"]doubleValue] : 0,y=[offset[@"y"]isKindOfClass:NSNumber.class] ? [offset[@"y"]doubleValue] : 0;
    if(!isfinite(x)||!isfinite(y))return p;
    p.x+=fmin(.75,fmax(-.75,x))*self.bounds.size.width;p.y+=fmin(.75,fmax(-.75,y))*self.bounds.size.height;
    CGFloat rx=fmin(radius,self.bounds.size.width/2),ry=fmin(radius,self.bounds.size.height/2);
    p.x=fmin(self.bounds.size.width-rx,fmax(rx,p.x));p.y=fmin(self.bounds.size.height-ry,fmax(ry,p.y));return p;
}
- (NSArray *)editingHandles {
    NSMutableArray *rows=[NSMutableArray new];
    NSArray *ids=@[@"leftStick",@"rightStick",@"face",@"dpad",@"shoulderL",@"shoulderR",@"clickL",@"clickR",@"minus",@"plus",@"layout"];
    NSArray *titles=@[@"L",@"R",@"ABXY",@"D-pad",@"ZL / L",@"ZR / R",@"L3",@"R3",@"−",@"+",@"2D / 3D"];
    CGPoint p[]={self.stickHome,self.rightHome,self.faceCenter,self.dpadCenter,[self dropCenter:B_ZL],[self dropCenter:B_ZR],[self clickCenter:B_LS],[self clickCenter:B_RS],CGPointMake(CGRectGetMidX([self pillRect:B_MINUS]),CGRectGetMidY([self pillRect:B_MINUS])),CGPointMake(CGRectGetMidX([self pillRect:B_PLUS]),CGRectGetMidY([self pillRect:B_PLUS])),self.swapCenter};
    for(NSUInteger i=0;i<ids.count;i++)[rows addObject:@{@"id":ids[i],@"title":titles[i],@"x":@(p[i].x/MAX(1,self.bounds.size.width)),@"y":@(p[i].y/MAX(1,self.bounds.size.height))}];return rows;
}
