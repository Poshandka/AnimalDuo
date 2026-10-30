// Opt-in, bounded diagnostics from actual drawable presentation timestamps.
// No display-link/UI refresh counter is used as a proxy for game frame rate.
#import <Foundation/Foundation.h>
#import <os/lock.h>
#include <mach/mach.h>
#include <stdatomic.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static dispatch_queue_t perfQueue;
static NSFileHandle *perfFile;
static os_unfair_lock perfLock=OS_UNFAIR_LOCK_INIT;
static _Atomic int perfEnabled;
static double perfStart,perfWindow,perfPrevious,perfSum,perfMaximum,perfMaximumGap;
static uint64_t perfCount,perfGaps,perfOver50,perfOver100,perfHistogram[2001];

static void perfWrite(NSDictionary *row) {
    if(!perfFile)return;
    NSData *json=[NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:nil];
    if(json)@try{[perfFile writeData:json];[perfFile writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];}@catch(NSException *e){atomic_store(&perfEnabled,0);fprintf(stderr,"performance: report write failed: %s\n",e.reason.UTF8String);}
}
static double perfPercentile(double fraction) {
    if(!perfCount)return 0;
    uint64_t want=(uint64_t)ceil(perfCount*fraction),n=0;
    for(unsigned i=0;i<2001;i++){n+=perfHistogram[i];if(n>=want)return i;}
    return 2000;
}
void dm_performance_presented(double timestamp) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        if(![NSUserDefaults.standardUserDefaults boolForKey:@"DmPerformanceRecord"])return;
        const char *path=getenv("DM_ROOT");if(!path || !*path)return;
        NSURL *root=[[NSURL fileURLWithPath:@(path) isDirectory:YES]URLByAppendingPathComponent:@"performance" isDirectory:YES];
        NSError *error;if(![NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error])return;
        NSString *name=[NSString stringWithFormat:@"%@-%@.jsonl",[NSISO8601DateFormatter.new stringFromDate:NSDate.date],NSUUID.UUID.UUIDString];
        name=[name stringByReplacingOccurrencesOfString:@":" withString:@"-"];
        NSURL *url=[root URLByAppendingPathComponent:name];
        if(![NSFileManager.defaultManager createFileAtPath:url.path contents:nil attributes:nil])return;
        perfFile=[NSFileHandle fileHandleForWritingToURL:url error:&error];if(!perfFile)return;
        perfQueue=dispatch_queue_create("dm.performance.report",DISPATCH_QUEUE_SERIAL);
        perfWrite(@{@"schema":@"nxnative-performance/1",@"event":@"start",@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"source":@"actual drawable presentedTime",@"limit_seconds":@1800,@"interval_resolution_ms":@1,@"gaps_over_2_seconds":@"reported separately; excluded from interval FPS"});
        atomic_store(&perfEnabled,1);fprintf(stderr,"performance: recording actual displayed frames for up to 30 minutes (%s)\n",url.lastPathComponent.UTF8String);
    });
    if(!atomic_load(&perfEnabled) || !isfinite(timestamp) || timestamp<=0)return;
    os_unfair_lock_lock(&perfLock);
    if(!perfStart){perfStart=perfWindow=perfPrevious=timestamp;os_unfair_lock_unlock(&perfLock);return;}
    // Presentation callbacks may arrive out of order; retain the last timestamp.
    if(timestamp<=perfPrevious){os_unfair_lock_unlock(&perfLock);return;}
    double interval=(timestamp-perfPrevious)*1000;perfPrevious=timestamp;
    if(interval>2000){perfGaps++;perfMaximumGap=fmax(perfMaximumGap,interval);}
    else {perfSum+=interval;perfCount++;perfMaximum=fmax(perfMaximum,interval);if(interval>50)perfOver50++;if(interval>100)perfOver100++;perfHistogram[(unsigned)fmin(2000,round(interval))]++;}
    BOOL finished=timestamp-perfStart>=1800;
    if(timestamp-perfWindow>=10 || finished) {
        NSDictionary *row=@{@"event":finished ? @"complete":@"window",@"elapsed_s":@(timestamp-perfStart),@"window_s":@(timestamp-perfWindow),@"displayed_intervals":@(perfCount),@"fps":@(perfSum>0 ? perfCount*1000.0/perfSum:0),@"p50_ms":@(perfPercentile(.5)),@"p95_ms":@(perfPercentile(.95)),@"p99_ms":@(perfPercentile(.99)),@"frame_max_ms":@(perfMaximum),@"intervals_over_50_ms":@(perfOver50),@"intervals_over_100_ms":@(perfOver100),@"gaps_over_2_s":@(perfGaps),@"gap_max_ms":@(perfMaximumGap)};
        dispatch_async(perfQueue,^{@autoreleasepool{
            NSMutableDictionary *record=[row mutableCopy];task_vm_info_data_t info;mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
            if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS)record[@"footprint_bytes"]=@(info.phys_footprint);
            record[@"thermal_state"]=@(NSProcessInfo.processInfo.thermalState);record[@"low_power"]=@(NSProcessInfo.processInfo.lowPowerModeEnabled);
            perfWrite(record);
            if(finished){[perfFile closeFile];perfFile=nil;}
        }});
        perfWindow=timestamp;perfCount=perfGaps=perfOver50=perfOver100=0;perfSum=perfMaximum=perfMaximumGap=0;memset(perfHistogram,0,sizeof perfHistogram);
        if(finished)atomic_store(&perfEnabled,0);
    }
    os_unfair_lock_unlock(&perfLock);
}
void dm_performance_flush(void) { if(perfQueue)dispatch_sync(perfQueue,^{}); }
