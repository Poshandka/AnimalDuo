#import "../performance_apple.m"
#include <assert.h>
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);BOOL enabled=strcmp(argv[2],"off")!=0;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"DmPerformanceRecord":@(enabled)} forName:NSArgumentDomain];
    setenv("DM_ROOT",argv[1],1);
    for(int i=0;i<55000;i++){
        double t=1+i/30.0+(i>=900 ? 3:0)+(i>=400 ? .2-1.0/30:0)+(i>=500 ? .06-1.0/30:0);dm_performance_presented(t);
        if(i==200)dm_performance_presented(t-1); // Late callback must not reverse time.
    }
    dm_performance_flush();
    NSURL *folder=[[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES]URLByAppendingPathComponent:@"performance"];
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil];
    if(!enabled){assert(!files.count);puts("Performance recorder disabled: no file or timer PASS");return 0;}
    assert(files.count==1);NSString *text=[NSString stringWithContentsOfURL:files[0] encoding:NSUTF8StringEncoding error:nil];
    int windows=0,gaps=0,over50=0,over100=0;double maximum=0,maximumGap=0;BOOL complete=NO;
    for(NSString *line in [text componentsSeparatedByString:@"\n"]){
        if(!line.length)continue;NSDictionary *r=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];assert(r);
        if([r[@"event"]isEqual:@"start"]){assert([r[@"source"]isEqual:@"actual drawable presentedTime"]);continue;}
        windows++;gaps+=[r[@"gaps_over_2_s"]intValue];
        assert([r[@"fps"]doubleValue]>=29 && [r[@"fps"]doubleValue]<=30.01 && [r[@"p99_ms"]intValue]==33);
        over50+=[r[@"intervals_over_50_ms"]intValue];over100+=[r[@"intervals_over_100_ms"]intValue];
        maximum=fmax(maximum,[r[@"frame_max_ms"]doubleValue]);maximumGap=fmax(maximumGap,[r[@"gap_max_ms"]doubleValue]);
        assert([r[@"footprint_bytes"]unsignedLongLongValue]>0);
        if([r[@"event"]isEqual:@"complete"]){complete=YES;assert([r[@"elapsed_s"]doubleValue]>=1800 && [r[@"elapsed_s"]doubleValue]<1801);}
    }
    assert(windows>=179 && windows<=181 && gaps==1 && complete);
    assert(over50==2 && over100==1 && fabs(maximum-200)<.01 && fabs(maximumGap-3033.333333)<.01);
    puts("Performance recorder: actual timestamps, rare hitch maxima/counts, separate pause gaps, footprint and 30-minute stop PASS");
}}
