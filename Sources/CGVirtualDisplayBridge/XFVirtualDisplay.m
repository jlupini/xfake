#import "XFVirtualDisplay.h"

// ---- Private API declarations (class-dump; from FluffyDisplay, Apache-2.0) ----
// These interfaces are ONLY used to message instances obtained via
// NSClassFromString — no link-time references to the private classes exist.

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNum;
@property (nonatomic, strong) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) void (^terminationHandler)(id sender);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) uint32_t hiDPI;
@property (nonatomic, strong) NSArray *modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

// ---- Wrapper ----

@implementation XFModeSpec
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate {
    if ((self = [super init])) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}
@end

@implementation XFVirtualDisplay {
    CGVirtualDisplay *_display; // strong ref = display lifetime
}

+ (BOOL)apiAvailable {
    return NSClassFromString(@"CGVirtualDisplay") != nil
        && NSClassFromString(@"CGVirtualDisplayDescriptor") != nil
        && NSClassFromString(@"CGVirtualDisplaySettings") != nil
        && NSClassFromString(@"CGVirtualDisplayMode") != nil;
}

- (nullable instancetype)initWithName:(NSString *)name
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                            serialNum:(uint32_t)serialNum
                             sizeInMM:(CGSize)sizeInMM
                                modes:(NSArray<XFModeSpec *> *)modes
                   terminationHandler:(nullable void (^)(void))terminationHandler {
    if (!(self = [super init])) return nil;
    if (![XFVirtualDisplay apiAvailable] || modes.count == 0) return nil;

    CGVirtualDisplayDescriptor *desc =
        [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    desc.name = name;
    desc.vendorID = vendorID;
    desc.productID = productID;
    desc.serialNum = serialNum;
    desc.sizeInMillimeters = sizeInMM;

    uint32_t maxW = 0, maxH = 0;
    for (XFModeSpec *m in modes) {
        maxW = MAX(maxW, m.width * 2);
        maxH = MAX(maxH, m.height * 2);
    }
    desc.maxPixelsWide = maxW;
    desc.maxPixelsHigh = maxH;

    // sRGB primaries (values used by FluffyDisplay and Chromium)
    desc.redPrimary   = CGPointMake(0.6797, 0.3203);
    desc.greenPrimary = CGPointMake(0.2559, 0.6983);
    desc.bluePrimary  = CGPointMake(0.1494, 0.0557);
    desc.whitePoint   = CGPointMake(0.3125, 0.3291);
    desc.queue = dispatch_get_main_queue();
    if (terminationHandler) {
        desc.terminationHandler = ^(id sender) { terminationHandler(); };
    }

    CGVirtualDisplay *display =
        [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    if (!display) return nil;

    CGVirtualDisplaySettings *settings =
        [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 1;
    NSMutableArray *cgModes = [NSMutableArray arrayWithCapacity:modes.count];
    for (XFModeSpec *m in modes) {
        [cgModes addObject:[[NSClassFromString(@"CGVirtualDisplayMode") alloc]
            initWithWidth:m.width height:m.height refreshRate:m.refreshRate]];
    }
    settings.modes = cgModes;

    if (![display applySettings:settings]) return nil;
    _display = display;
    return self;
}

- (CGDirectDisplayID)displayID {
    return _display.displayID;
}

@end
