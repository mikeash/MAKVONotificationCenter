//
//  MAKVONotificationCenter_Tests.m
//  MAKVONotificationCenter-Tests
//
//  Created by Gwynne on 12/1/11.
//

#import "Tests.h"
#import "MAKVONotificationCenter.h"

/******************************************************************************/
@interface TestObject : NSObject
@property(nonatomic,assign)	BOOL			toggle;
@end

@implementation TestObject
@synthesize toggle;
- (void)dealloc
{
    NSLog(@"I exist, therefore I am");
}
@end

/******************************************************************************/
@interface MAKVONotificationCenter_Tests ()
{
    BOOL		_triggered;
}
@end

/******************************************************************************/
@implementation MAKVONotificationCenter_Tests

- (void)observePath:(NSString *)keyPath object:(id)object change:(NSDictionary *)change info:(id)info
{
    STAssertEqualObjects(info, @"test", @"User info was wrong: expected \"test\", got %@", info);
    _triggered = YES;
}

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testBasicObserving
{
    TestObject				*tester = [[TestObject alloc] init];
    id<MAKVOObservation>	observation = nil;
    
    _triggered = NO;
    [tester addObserver:self keyPath:@"toggle" selector:@selector(observePath:object:change:info:) userInfo:@"test" options:0];
    tester.toggle = YES;
    STAssertTrue(_triggered, @"Basic observation was not fired");
    
    _triggered = NO;
    [tester removeObserver:self keyPath:@"toggle" selector:@selector(observePath:object:change:info:)];
    tester.toggle = NO;
    STAssertFalse(_triggered, @"Basic observation was not removed");
    
    _triggered = NO;
    observation = [tester addObserver:self keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { _triggered = YES; }];
    STAssertNotNil(observation, @"nil observation returned");
    tester.toggle = YES;
    STAssertTrue(_triggered, @"Basic block observation was not fired");
    
    _triggered = NO;
    [observation remove];
    tester.toggle = NO;
    STAssertFalse(_triggered, @"Basic block observation was not removed");
}

- (void)testAutoDeregistration
{
    TestObject				*tester1 = [[TestObject alloc] init];
    id<MAKVOObservation>	observation = nil;
        
    @autoreleasepool
    {
        TestObject			*observer1 = [[TestObject alloc] init];

        observation = [tester1 addObserver:observer1 keyPath:@"toggle" options:0 block:^(MAKVONotification *notification) { _triggered = YES; }];
        // tester is deallocated here.
    }
    STAssertFalse(observation.isValid, @"Observation was not automatically removed when observer was deallocated.");
    
    TestObject				*observer2 = [[TestObject alloc] init];

    @autoreleasepool
    {
        TestObject			*tester2 = [[TestObject alloc] init];
        
        observation = [tester2 addObserver:observer2 keyPath:@"toggle" options:0 block:^(MAKVONotification *notification) { _triggered = YES; }];
    }
    STAssertFalse(observation.isValid, @"Observation was not automatically removed when target was deallocated.");
}

@end

/*
    MAKeyValueObservingOptionUnregisterManually		= 0x80000000,
    MAKeyValueObservingOptionNoInformation			= 0x40000000,
- (id<MAKVOObservation>)addObserver:(id)observer
                            keyPath:(id<MAKVOKeyPath>)keyPath
                           selector:(SEL)selector
                           userInfo:(id)userInfo
                            options:(NSKeyValueObservingOptions)options;
- (id<MAKVOObservation>)observeTarget:(id)target
                              keyPath:(id<MAKVOKeyPath>)keyPath
                             selector:(SEL)selector
                             userInfo:(id)userInfo
                              options:(NSKeyValueObservingOptions)options;
- (id<MAKVOObservation>)addObserver:(id)observer
                            keyPath:(id<MAKVOKeyPath>)keyPath
                            options:(NSKeyValueObservingOptions)options
                              block:(void (^)(MAKVONotification *notification))block;
- (id<MAKVOObservation>)observeTarget:(id)target
                              keyPath:(id<MAKVOKeyPath>)keyPath
                              options:(NSKeyValueObservingOptions)options
                                block:(void (^)(MAKVONotification *notification))block;
- (void)removeAllObservers;
- (void)stopObservingAllTargets;
- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath;
- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath;
- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;
- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;

+ (id)defaultCenter;
// selector should have the following signature:
//	- (void)observeValueForKeyPath:(NSString *)keyPath
//						  ofObject:(id)target
//							change:(NSDictionary *)change
//						  userInfo:(id)userInfo;
- (id<MAKVOObservation>)addObserver:(id)observer
                             object:(id)target
                            keyPath:(id<MAKVOKeyPath>)keyPath
                           selector:(SEL)selector
                           userInfo:(id)userInfo
                            options:(NSKeyValueObservingOptions)options;
- (id<MAKVOObservation>)addObserver:(id)observer
                             object:(id)target
                            keyPath:(id<MAKVOKeyPath>)keyPath
                            options:(NSKeyValueObservingOptions)options
                              block:(void (^)(MAKVONotification *notification))block;
- (void)removeObserver:(id)observer object:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;
- (void)removeObservation:(id<MAKVOObservation>)observation;
*/
