#import "FlutterSaltyrtcClientPlugin.h"
#if __has_include(<flutter_saltyrtc_client/flutter_saltyrtc_client-Swift.h>)
#import <flutter_saltyrtc_client/flutter_saltyrtc_client-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "flutter_saltyrtc_client-Swift.h"
#endif

@implementation FlutterSaltyrtcClientPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterSaltyrtcClientPlugin registerWithRegistrar:registrar];
}
@end
