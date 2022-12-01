#import <Flutter/Flutter.h>




@interface PipFlutterPlugin : NSObject <FlutterPlugin,FlutterPlatformViewFactory>

@property(readonly, weak, nonatomic) NSObject<FlutterBinaryMessenger>* messenger;
@property(readonly, strong, nonatomic) NSMutableDictionary* players;
@property(readonly, strong, nonatomic) NSObject<FlutterPluginRegistrar>* registrar;

+(instancetype) shareInstance;
- (void)viewWillDisappear;
@end
