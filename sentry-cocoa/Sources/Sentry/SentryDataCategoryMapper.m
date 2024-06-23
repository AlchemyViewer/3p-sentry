#import "SentryDataCategoryMapper.h"
#import "SentryDataCategory.h"
#import "SentryEnvelopeItemType.h"
#import <Foundation/Foundation.h>

NSString *const kSentryDataCategoryNameAll = @"";
NSString *const kSentryDataCategoryNameDefault = @"default";
NSString *const kSentryDataCategoryNameError = @"error";
NSString *const kSentryDataCategoryNameSession = @"session";
NSString *const kSentryDataCategoryNameTransaction = @"transaction";
NSString *const kSentryDataCategoryNameAttachment = @"attachment";
NSString *const kSentryDataCategoryNameUserFeedback = @"user_report";
NSString *const kSentryDataCategoryNameProfile = @"profile";
NSString *const kSentryDataCategoryNameProfileChunk = @"profile_chunk";
NSString *const kSentryDataCategoryNameReplay = @"replay";
NSString *const kSentryDataCategoryNameMetricBucket = @"metric_bucket";
NSString *const kSentryDataCategoryNameUnknown = @"unknown";

NS_ASSUME_NONNULL_BEGIN

SentryDataCategory
sentryDataCategoryForEnvelopItemType(NSString *itemType)
{
    if ([itemType isEqualToString:SentryEnvelopeItemTypeEvent]) {
        return kSentryDataCategoryError;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeSession]) {
        return kSentryDataCategorySession;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeTransaction]) {
        return kSentryDataCategoryTransaction;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeAttachment]) {
        return kSentryDataCategoryAttachment;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeProfile]) {
        return kSentryDataCategoryProfile;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeProfileChunk]) {
        return kSentryDataCategoryProfileChunk;
    }
    if ([itemType isEqualToString:SentryEnvelopeItemTypeReplayVideo]) {
        return kSentryDataCategoryReplay;
    }
    // The envelope item type used for metrics is statsd whereas the client report category for
    // discarded events is metric_bucket.
    if ([itemType isEqualToString:SentryEnvelopeItemTypeStatsd]) {
        return kSentryDataCategoryMetricBucket;
    }
    return kSentryDataCategoryDefault;
}

SentryDataCategory
sentryDataCategoryForNSUInteger(NSUInteger value)
{
    if (value < 0 || value > kSentryDataCategoryUnknown) {
        return kSentryDataCategoryUnknown;
    }

    return (SentryDataCategory)value;
}

SentryDataCategory
sentryDataCategoryForString(NSString *value)
{
    if ([value isEqualToString:kSentryDataCategoryNameAll]) {
        return kSentryDataCategoryAll;
    }
    if ([value isEqualToString:kSentryDataCategoryNameDefault]) {
        return kSentryDataCategoryDefault;
    }
    if ([value isEqualToString:kSentryDataCategoryNameError]) {
        return kSentryDataCategoryError;
    }
    if ([value isEqualToString:kSentryDataCategoryNameSession]) {
        return kSentryDataCategorySession;
    }
    if ([value isEqualToString:kSentryDataCategoryNameTransaction]) {
        return kSentryDataCategoryTransaction;
    }
    if ([value isEqualToString:kSentryDataCategoryNameAttachment]) {
        return kSentryDataCategoryAttachment;
    }
    if ([value isEqualToString:kSentryDataCategoryNameUserFeedback]) {
        return kSentryDataCategoryUserFeedback;
    }
    if ([value isEqualToString:kSentryDataCategoryNameProfile]) {
        return kSentryDataCategoryProfile;
    }
    if ([value isEqualToString:kSentryDataCategoryNameProfileChunk]) {
        return kSentryDataCategoryProfileChunk;
    }
    if ([value isEqualToString:kSentryDataCategoryNameReplay]) {
        return kSentryDataCategoryReplay;
    }
    if ([value isEqualToString:kSentryDataCategoryNameMetricBucket]) {
        return kSentryDataCategoryMetricBucket;
    }

    return kSentryDataCategoryUnknown;
}

NSString *
nameForSentryDataCategory(SentryDataCategory category)
{
    if (category < kSentryDataCategoryAll && category > kSentryDataCategoryUnknown) {
        return kSentryDataCategoryNameUnknown;
    }

    switch (category) {
    case kSentryDataCategoryAll:
        return kSentryDataCategoryNameAll;
    case kSentryDataCategoryDefault:
        return kSentryDataCategoryNameDefault;
    case kSentryDataCategoryError:
        return kSentryDataCategoryNameError;
    case kSentryDataCategorySession:
        return kSentryDataCategoryNameSession;
    case kSentryDataCategoryTransaction:
        return kSentryDataCategoryNameTransaction;
    case kSentryDataCategoryAttachment:
        return kSentryDataCategoryNameAttachment;
    case kSentryDataCategoryUserFeedback:
        return kSentryDataCategoryNameUserFeedback;
    case kSentryDataCategoryProfile:
        return kSentryDataCategoryNameProfile;
    case kSentryDataCategoryProfileChunk:
        return kSentryDataCategoryNameProfileChunk;
    case kSentryDataCategoryMetricBucket:
        return kSentryDataCategoryNameMetricBucket;
    case kSentryDataCategoryUnknown:
        return kSentryDataCategoryNameUnknown;
    case kSentryDataCategoryReplay:
        return kSentryDataCategoryNameReplay;
    }
}

NS_ASSUME_NONNULL_END
