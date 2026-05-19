#import "TransifyrSubtitleStore.h"

static NSString * const TransifyrAppGroupIdentifier = @"group.com.vteen.RealtimeTranslator";
static NSString * const TransifyrTranslationKey = @"broadcast_current_translation";
static NSString * const TransifyrTimestampKey = @"broadcast_current_translation_at";
static NSTimeInterval const TransifyrSubtitleFreshnessWindow = 4.0;

@interface TransifyrSubtitleStore ()
@property(nonatomic, strong) NSUserDefaults *defaults;
@property(nonatomic, assign) NSTimeInterval lastConsumedTimestamp;
@end

@implementation TransifyrSubtitleStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:TransifyrAppGroupIdentifier] ?: NSUserDefaults.standardUserDefaults;
    }
    return self;
}

- (NSString *)currentTranslation {
    if (![self hasFreshTranslation]) {
        return @"";
    }

    NSString *translation = [self.defaults stringForKey:TransifyrTranslationKey] ?: @"";
    return [translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)consumeNewTranslation {
    NSTimeInterval timestamp = [self.defaults doubleForKey:TransifyrTimestampKey];
    if (timestamp <= self.lastConsumedTimestamp || ![self hasFreshTranslation]) {
        return @"";
    }

    self.lastConsumedTimestamp = timestamp;
    return [self currentTranslation];
}

- (BOOL)hasFreshTranslation {
    NSTimeInterval timestamp = [self.defaults doubleForKey:TransifyrTimestampKey];
    if (timestamp <= 0) {
        return NO;
    }

    NSTimeInterval age = NSDate.date.timeIntervalSince1970 - timestamp;
    return age >= 0 && age <= TransifyrSubtitleFreshnessWindow;
}

@end
