// React Native native module (legacy API, works through the New Architecture interop layer).
#import <React/RCTBridgeModule.h>
#import <mach/mach.h>
#import <os/proc.h>

@interface SpikeBridge : NSObject <RCTBridgeModule>
@end

@implementation SpikeBridge
RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup { return NO; }

RCT_EXPORT_METHOD(hostCall:(NSString *)method arg:(NSString *)arg)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SpikeHostCall" object:nil
                                                      userInfo:@{@"method": method ?: @"", @"arg": arg ?: @""}];
  });
}

RCT_EXPORT_METHOD(openAuthSession)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SpikeAuth" object:nil];
  });
}

RCT_EXPORT_METHOD(memory:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
  resolve(@{@"available": @(os_proc_available_memory()), @"footprint": @(kr == KERN_SUCCESS ? info.phys_footprint : 0)});
}
@end
