// Included by the iOS entry point and the standalone filesystem contract test.
#import "ResourceStore.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
static NSError *resourceError(NSString *text,NSInteger code){return [NSError errorWithDomain:@"nxnative.resources" code:code userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSString *resourceDigest(NSData *data){unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof digest;i++)[s appendFormat:@"%02x",digest[i]];return s;}
static BOOL resourceHex(id value,NSUInteger length){return [value isKindOfClass:NSString.class] && [value length]==length && [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location==NSNotFound;}
static BOOL resourcePath(id value){
    if(![value isKindOfClass:NSString.class] || ![value length] || [value length]>1500 || [value isAbsolutePath] || [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return NO;
    for(NSString *p in [value componentsSeparatedByString:@"/"])if(!p.length || [p isEqual:@"."] || [p isEqual:@".."] || [p containsString:@":"])return NO;
    return [value hasPrefix:@"romfs/"] || [value hasPrefix:@"msl/"] || [value hasPrefix:@"aoc/"] || [value hasPrefix:@"pso/"] || [value hasPrefix:@"dm/font/"];
}
static BOOL resourceDirectoryPath(id value){return [@[@"romfs",@"msl",@"aoc",@"pso",@"dm/font"]containsObject:value] || resourcePath(value);}
static BOOL resourceInside(NSURL *root,NSURL *file){NSString *base=root.URLByResolvingSymlinksInPath.path,*actual=file.URLByResolvingSymlinksInPath.path;return [actual hasPrefix:[base stringByAppendingString:@"/"]];}
static NSString *resourceFileHash(NSURL *url,BOOL (^cancelled)(void),NSError **error){
    NSInputStream *stream=[NSInputStream inputStreamWithURL:url];[stream open];CC_SHA256_CTX state;CC_SHA256_Init(&state);uint8_t bytes[128u<<10];NSInteger n;NSError *failure=nil;
    while((n=[stream read:bytes maxLength:sizeof bytes])>0){if(cancelled && cancelled()){failure=resourceError(@"Resource installation paused.",2);break;}CC_SHA256_Update(&state,bytes,(CC_LONG)n);}
    if(n<0)failure=stream.streamError;[stream close];if(failure){if(error)*error=failure;return nil;}
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&state);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof digest;i++)[s appendFormat:@"%02x",digest[i]];return s;
}
@interface DMResourceStore()
@property NSURL *bundle,*directory,*parent;
@property NSDictionary *requirements;
@property NSError *configurationError;
@end
@implementation DMResourceStore
- (instancetype)initWithBundle:(NSURL *)bundle support:(NSURL *)support title:(NSString *)title version:(NSString *)version chain:(NSString *)chain{
    if((self=[super init])){
        _bundle=bundle;_requirements=[NSDictionary dictionaryWithContentsOfURL:[bundle URLByAppendingPathComponent:@"dm/resource-set.plist"]]?:@{};
        NSDictionary *r=_requirements;
        BOOL valid=[r[@"format"]isEqual:@1] && resourceHex([title lowercaseString],16) && resourceHex(r[@"id"],64) && resourceHex(r[@"manifestSHA256"],64) && [r[@"title"]isEqual:title] && [r[@"version"]isEqual:version] && [r[@"files"]isKindOfClass:NSNumber.class] && [r[@"files"]unsignedIntegerValue]>0 && [r[@"files"]unsignedIntegerValue]<=1000000 && [r[@"bytes"]isKindOfClass:NSNumber.class] && [r[@"bytes"]unsignedLongLongValue]>0 && [r[@"checks"]isKindOfClass:NSArray.class] && [r[@"checks"]count]>0 && [r[@"checks"]count]<=32 && [r[@"directories"]isKindOfClass:NSArray.class] && [r[@"directories"]count]<=32 && [r[@"manifestBytes"]isKindOfClass:NSNumber.class] && [r[@"manifestBytes"]unsignedLongLongValue]>0 && [r[@"manifestBytes"]unsignedLongLongValue]<=(256u<<20);
        valid=valid && [r[@"chain"]isEqual:chain];
        if(!valid)_configurationError=resourceError(@"The resource requirements are invalid. Install the complete version.",1);
        _parent=[[support URLByAppendingPathComponent:@"nxnative-resources" isDirectory:YES]URLByAppendingPathComponent:valid?r[@"title"]:@"invalid" isDirectory:YES];
        _directory=[_parent URLByAppendingPathComponent:valid?r[@"id"]:@"invalid" isDirectory:YES];
    }return self;
}
- (BOOL)regular:(NSURL *)file size:(NSNumber *)size root:(NSURL *)root{
    struct stat st;return resourceInside(root,file) && !lstat(file.fileSystemRepresentation,&st) && S_ISREG(st.st_mode) && st.st_size>=0 && (uint64_t)st.st_size==size.unsignedLongLongValue;
}
- (BOOL)ready:(NSError **)error{
    if(self.configurationError){if(error)*error=self.configurationError;return NO;}
    NSDictionary *receipt=[NSDictionary dictionaryWithContentsOfURL:[self.directory URLByAppendingPathComponent:@"installed.plist"]];
    for(NSString *key in @[@"format",@"id",@"title",@"version",@"manifestSHA256",@"files",@"bytes"])if(![receipt[key]isEqual:self.requirements[key]])return NO;
    // Installation verifies every byte. Startup checks the pinned receipt and
    // critical files rather than rehashing many gigabytes before UIApplication.
    for(NSDictionary *check in self.requirements[@"checks"]){
        if(![check isKindOfClass:NSDictionary.class] || !resourcePath(check[@"path"]) || ![check[@"size"]isKindOfClass:NSNumber.class])return NO;
        NSURL *file=[self.directory URLByAppendingPathComponent:check[@"path"]];
        if(![self regular:file size:check[@"size"] root:self.directory])return NO;
        if(check[@"sha256"] && (!resourceHex(check[@"sha256"],64) || [check[@"size"]unsignedLongLongValue]>(4u<<20) || ![resourceFileHash(file,nil,nil)isEqual:check[@"sha256"]]))return NO;
    }
    for(NSString *path in self.requirements[@"directories"]){struct stat st;NSURL *dir=[self.directory URLByAppendingPathComponent:path];if(!resourceDirectoryPath(path) || !resourceInside(self.directory,dir) || lstat(dir.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode))return NO;}
    return YES;
}
- (BOOL)hasInstaller{return [NSFileManager.defaultManager fileExistsAtPath:[self.bundle URLByAppendingPathComponent:@"dm/resource-files.plist"].path];}
- (NSDictionary *)inventory:(NSError **)error{
    if(self.configurationError){if(error)*error=self.configurationError;return nil;}
    NSURL *url=[self.bundle URLByAppendingPathComponent:@"dm/resource-files.plist"];
    if(![self regular:url size:self.requirements[@"manifestBytes"] root:self.bundle]){if(error)*error=resourceError(@"The resource installer is missing or damaged.",1);return nil;}
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];if(!data)return nil;
    if(![resourceDigest(data)isEqual:self.requirements[@"manifestSHA256"]]){if(error)*error=resourceError(@"The resource installer is damaged. Install the complete version again.",1);return nil;}
    NSDictionary *manifest=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:error];
    if(![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"id"]isEqual:self.requirements[@"id"]] || ![manifest[@"files"]isKindOfClass:NSArray.class] || [manifest[@"files"]count]!=[self.requirements[@"files"]unsignedIntegerValue]){if(error)*error=resourceError(@"The resource inventory is invalid.",1);return nil;}
    if(![manifest[@"directories"]isKindOfClass:NSArray.class]){if(error)*error=resourceError(@"The resource directory inventory is invalid.",1);return nil;}
    NSMutableSet *seen=[NSMutableSet new];uint64_t total=0;
    for(NSString *path in manifest[@"directories"]){if(!resourceDirectoryPath(path) || [seen containsObject:path]){if(error)*error=resourceError(@"The resource directory inventory is invalid.",1);return nil;}[seen addObject:path];}
    for(NSDictionary *row in manifest[@"files"]){
        if(![row isKindOfClass:NSDictionary.class] || !resourcePath(row[@"path"]) || [seen containsObject:row[@"path"]] || !resourceHex(row[@"sha256"],64) || ![row[@"size"]isKindOfClass:NSNumber.class] || [row[@"size"]longLongValue]<0 || [row[@"size"]unsignedLongLongValue]>UINT64_MAX-total){if(error)*error=resourceError(@"The resource inventory has unsupported paths or sizes.",1);return nil;}
        [seen addObject:row[@"path"]];total+=[row[@"size"]unsignedLongLongValue];
    }
    if(total!=[self.requirements[@"bytes"]unsignedLongLongValue]){if(error)*error=resourceError(@"The resource inventory size does not match.",1);return nil;}
    return manifest;
}
- (BOOL)installFile:(NSDictionary *)row stage:(NSURL *)stage cancelled:(BOOL (^)(void))cancelled error:(NSError **)error{
    NSFileManager *fm=NSFileManager.defaultManager;
        if(cancelled && cancelled()){if(error)*error=resourceError(@"Resource installation paused.",2);return NO;}
        NSString *path=row[@"path"];NSURL *source=[self.bundle URLByAppendingPathComponent:path],*target=[stage URLByAppendingPathComponent:path];
        if(![self regular:source size:row[@"size"] root:self.bundle] || !resourceInside(stage,target)){if(error)*error=resourceError(@"A resource file is missing or has an unsupported path.",1);return NO;}
        BOOL valid=[self regular:target size:row[@"size"] root:stage] && [[resourceFileHash(target,cancelled,error) description]isEqual:row[@"sha256"]];
        if(!valid){
            if(error && *error)return NO;
            if(![fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error])return NO;
            NSURL *partial=[target URLByAppendingPathExtension:@"partial"];if(!resourceInside(stage,partial)){if(error)*error=resourceError(@"The resource destination is invalid.",1);return NO;}
            [fm removeItemAtURL:partial error:nil];
            // APFS clones avoid a second physical copy. Other filesystems use
            // Foundation's copy, and disk-full errors retain resumable staging.
            if(clonefile(source.fileSystemRepresentation,partial.fileSystemRepresentation,0)){[fm removeItemAtURL:partial error:nil];if(![fm copyItemAtURL:source toURL:partial error:error])return NO;}
            NSString *actual=resourceFileHash(partial,cancelled,error);
            if(![actual isEqual:row[@"sha256"]]){if(error && !*error)*error=resourceError(@"A copied resource failed verification. The game has not started.",1);return NO;}
            [fm removeItemAtURL:target error:nil];if(![fm moveItemAtURL:partial toURL:target error:error])return NO;
        }
    return YES;
}
- (BOOL)installWithProgress:(void (^)(uint64_t,uint64_t,NSUInteger,NSUInteger))progress cancelled:(BOOL (^)(void))cancelled error:(NSError **)error{
    if([self ready:nil])return YES;
    NSDictionary *manifest=[self inventory:error];if(!manifest)return NO;
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:self.parent withIntermediateDirectories:YES attributes:nil error:error])return NO;
    [self.parent setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    NSURL *stage=[self.parent URLByAppendingPathComponent:[self.requirements[@"id"]stringByAppendingString:@".installing"] isDirectory:YES];
    if(!resourceInside(self.parent,stage) || ![fm createDirectoryAtURL:stage withIntermediateDirectories:YES attributes:nil error:error])return NO;
    for(NSString *path in manifest[@"directories"]){NSURL *dir=[stage URLByAppendingPathComponent:path];if(!resourceInside(stage,dir) || ![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error])return NO;}
    uint64_t done=0,total=[self.requirements[@"bytes"]unsignedLongLongValue];NSUInteger index=0,count=[manifest[@"files"]count];CFAbsoluteTime last=0;
    if(progress)progress(0,total,0,count);
    for(NSDictionary *row in manifest[@"files"]){
        // Keep the NSError strong outside the per-file pool. ARC writes the
        // callee's autoreleasing error back before that pool is drained.
        NSError *failure=nil;BOOL ok;
        @autoreleasepool{ok=[self installFile:row stage:stage cancelled:cancelled error:&failure];}
        if(!ok){if(error)*error=failure;return NO;}
        done+=[row[@"size"]unsignedLongLongValue];index++;
        CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();if(progress && (now-last>.1 || index==count)){progress(done,total,index,count);last=now;}
    }
    NSMutableDictionary *receipt=[self.requirements mutableCopy];receipt[@"verifiedAt"]=[NSDate date];
    if(![receipt writeToURL:[stage URLByAppendingPathComponent:@"installed.plist"] atomically:YES]){if(error)*error=resourceError(@"The resource installation could not be recorded.",1);return NO;}
    if([fm fileExistsAtPath:self.directory.path]){
        NSURL *old=[self.parent URLByAppendingPathComponent:[self.requirements[@"id"]stringByAppendingFormat:@".incomplete-%@",NSUUID.UUID.UUIDString]];
        if(!resourceInside(self.parent,self.directory) || ![fm moveItemAtURL:self.directory toURL:old error:error])return NO;
    }
    if(![fm moveItemAtURL:stage toURL:self.directory error:error])return NO;
    if(![self ready:error]){if(error && !*error)*error=resourceError(@"The installed resource set is incomplete.",1);return NO;}
    fprintf(stderr,"resources: verified %lu files, %llu bytes; persistent set ready\n",(unsigned long)count,(unsigned long long)total);return YES;
}
@end
