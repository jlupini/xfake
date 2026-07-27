#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// One logical (point) mode; the virtual display is always HiDPI (2x backing).
@interface XFModeSpec : NSObject
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) double refreshRate;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

/// Owns one CGVirtualDisplay. The display exists as long as this object lives;
/// deallocating it unplugs the display.
@interface XFVirtualDisplay : NSObject

/// NO if the private CGVirtualDisplay classes are missing on this OS.
+ (BOOL)apiAvailable;

/// Returns nil if the API is unavailable or applySettings: fails.
/// The handler must not strongly capture this XFVirtualDisplay (retain cycle;
/// the display would never unplug).
- (nullable instancetype)initWithName:(NSString *)name
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                            serialNum:(uint32_t)serialNum
                             sizeInMM:(CGSize)sizeInMM
                                modes:(NSArray<XFModeSpec *> *)modes
                   terminationHandler:(nullable void (^)(void))terminationHandler;

@property (nonatomic, readonly) CGDirectDisplayID displayID;

@end

NS_ASSUME_NONNULL_END
