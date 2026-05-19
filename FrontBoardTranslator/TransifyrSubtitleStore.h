#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TransifyrSubtitleStore : NSObject

- (NSString *)currentTranslation;
- (NSString *)consumeNewTranslation;
- (BOOL)hasFreshTranslation;

@end

NS_ASSUME_NONNULL_END
