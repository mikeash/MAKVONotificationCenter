//
//  MAKVONotificationCenter_Tests.m
//  MAKVONotificationCenter-Tests
//
//  Created by Gwynne on 12/1/11.
//

#import "Tests.h"
#import "MAKVONotificationCenter.h"

// IMPORTANT NOTE:
//	Several of these tests do a lot of very odd dancing around with autoreleases
//	and seemingly phantom retains. All of this is unfortunately necessary in
//	order to test the automatic deregistration semantics correctly; doing it
//	with ARC turned on would have been even uglier. Autorelease pools have to be
//	drained at the right times and observation objects properly retained in
//	order to control the object lifetimes without losing them prematurely. It's
//	evil.

/******************************************************************************/
@interface TestObserver : NSObject
{
  @public
    BOOL		_triggered, _triggered2;
}
@end

@implementation TestObserver

- (void)observePath:(NSString *)keyPath object:(id)object change:(NSDictionary *)change info:(id)info
{
//	STAssertEqualObjects(info, @"test", @"User info was wrong: expected \"test\", got %@", info);
    _triggered = YES;
}

- (void)observePath2:(NSString *)keyPath object:(id)object change:(NSDictionary *)change info:(id)info
{
//	STAssertEqualObjects(info, @"test", @"User info was wrong: expected \"test\", got %@", info);
    _triggered2 = YES;
}

@end

/******************************************************************************/
@interface TestObject : NSObject
@property(nonatomic,assign)	BOOL			toggle, toggle2;
@end

@implementation TestObject
@synthesize toggle, toggle2;
@end

/******************************************************************************/
@interface TestKeyPaths : NSObject <MAKVOKeyPathSet>
@end

@implementation TestKeyPaths
- (id<NSFastEnumeration>)ma_keyPathsAsSetOfStrings { return [NSSet setWithObjects:@"toggle", @"toggle2", nil]; }
@end

/******************************************************************************/
@interface DeallocTesterSuperclass : NSObject
@end
@implementation DeallocTesterSuperclass
- (void)dealloc { [super dealloc]; }
@end

@interface DeallocTesterSubclass : DeallocTesterSuperclass
@end
@implementation DeallocTesterSubclass
- (void)dealloc { [super dealloc]; }
@end

/******************************************************************************/
@interface MAKVONotificationCenter_Tests ()
@end

/******************************************************************************/
@implementation MAKVONotificationCenter_Tests

- (void)testBasicObserving
{
    @autoreleasepool
    {
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        id<MAKVOObservation>	observation = nil;
        
        observer->_triggered = NO;
        observation = [target addObserver:observer keyPath:@"toggle" selector:@selector(observePath:object:change:info:) userInfo:@"test" options:0];
        target.toggle = YES;
        STAssertTrue(observer->_triggered, @"Basic observation was not fired");
        
        observer->_triggered = NO;
        [target removeObserver:observer keyPath:@"toggle" selector:@selector(observePath:object:change:info:)];
        target.toggle = NO;
        STAssertFalse(observer->_triggered, @"Basic observation was not removed");
        STAssertFalse(observation.isValid, @"Basic observation was not invalidated");
        
        observer->_triggered = NO;
        observation = [target addObserver:observer keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { observer->_triggered = YES; }];
        STAssertNotNil(observation, @"nil observation returned");
        target.toggle = YES;
        STAssertTrue(observer->_triggered, @"Basic block observation was not fired");
        
        observer->_triggered = NO;
        [observation remove];
        target.toggle = NO;
        STAssertFalse(observer->_triggered, @"Basic block observation was not removed");
        STAssertFalse(observation.isValid, @"Basic block observation was not invalidated");
    }
}

- (void)testReversedObserving
{
    @autoreleasepool
    {
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        id<MAKVOObservation>	observation = nil;
        
        observer->_triggered = NO;
        observation = [observer observeTarget:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:) userInfo:@"test" options:0];
        target.toggle = YES;
        STAssertTrue(observer->_triggered, @"Reversed observation was not fired");
        
        observer->_triggered = NO;
        [observer stopObserving:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)];
        target.toggle = NO;
        STAssertFalse(observer->_triggered, @"Reversed observation was not removed");
        STAssertFalse(observation.isValid, @"Reversed observation was not invalidated");
        
        observer->_triggered = NO;
        observation = [observer observeTarget:target keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { observer->_triggered = YES; }];
        STAssertNotNil(observation, @"nil observation returned");
        target.toggle = YES;
        STAssertTrue(observer->_triggered, @"Reversed block observation was not fired");
        
        observer->_triggered = NO;
        [observation remove];
        target.toggle = NO;
        STAssertFalse(observer->_triggered, @"Reversed block observation was not removed");
        STAssertFalse(observation.isValid, @"Reversed block observation was not invalidated");
    }
}

- (void)testAutoDeregistrationObserver
{
    @autoreleasepool
    {
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        TestObserver			__block *observer = [[TestObserver alloc] init];
        id<MAKVOObservation>	observation = nil;
        
        @autoreleasepool
        {
            observation = [[target addObserver:observer keyPath:@"toggle" options:0
                                   block:^ (MAKVONotification *notification) { observer->_triggered = YES; }] retain];
        }
        [observation autorelease];	// balance artificial retain, but do NOT release yet!
        [observer release];
        STAssertFalse(observation.isValid, @"Observation was not automatically removed when observer was deallocated.");
    }
}

- (void)testAutoDeregistrationTarget
{
    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target = [[TestObject alloc] init];
        id<MAKVOObservation>	observation = nil;
        
        @autoreleasepool
        {
            observation = [[target addObserver:observer keyPath:@"toggle" options:0
                                   block:^(MAKVONotification *notification) { observer->_triggered = YES; }] retain];
        }
        [observation autorelease];
        [target release];
        STAssertFalse(observation.isValid, @"Observation was not automatically removed when target was deallocated.");
    }
}

- (void)testManualDeregistrationObserver
{
    @autoreleasepool
    {
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        TestObserver			__block *observer = [[TestObserver alloc] init];
        id<MAKVOObservation>	observation = nil;
        
        @autoreleasepool
        {
            observation = [[target addObserver:observer keyPath:@"toggle" options:MAKeyValueObservingOptionUnregisterManually
                                  block:^ (MAKVONotification *notification) { observer->_triggered = YES; }] retain];
        }
        [observation autorelease];
        [observer release];
        STAssertTrue(observation.isValid, @"Observation was automatically removed, but shouldn't have been.");
    
        [observation remove];
        STAssertFalse(observation.isValid, @"Observation was not manually removed.");
    }
}

/*
// THIS TEST CORRUPTS MEMORY AND CAN NOT BE IMPLEMENTED CORRECTLY.
- (void)testManualDeregistrationTarget
{
    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target = [[TestObject alloc] init];
        id<MAKVOObservation>	observation = nil;
    
        @autoreleasepool
        {
            observation = [[target addObserver:observer keyPath:@"toggle" options:MAKeyValueObservingOptionUnregisterManually
                                  block:^ (MAKVONotification *notification) { observer->_triggered = YES; }] retain];
        }
        [observation autorelease];
        [target release];
        STAssertTrue(observation.isValid, @"Observation was automatically removed, but shouldn't have been.");
        
        [observation remove];
        STAssertFalse(observation.isValid, @"Observation was not manually removed.");
    }
}
*/

- (void)testOptions
{
    @autoreleasepool
    {
        TestObserver			__block *observer = [[[TestObserver alloc] init] autorelease];
        TestObject				__block *target = [[[TestObject alloc] init] autorelease];
        id<MAKVOObservation>	observation = nil;
    
        observation = [observer observeTarget:target keyPath:@"toggle"
                                options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                                block:
        ^ (MAKVONotification *notification) {
            STAssertEqualObjects(notification.keyPath, @"toggle", @"Expected keyPath of \"toggle\", got \"%@\"", notification.keyPath);
            STAssertEqualObjects(notification.observer, observer, @"Expected observer to be %@, got %@", observer, notification.observer);
            STAssertEqualObjects(notification.target, target, @"Expected target to be %@, got %@", target, notification.target);
            STAssertEquals(notification.kind, (NSKeyValueChange)NSKeyValueChangeSetting, @"Expected kind to be \"setting\", got %lu", notification.kind);
            STAssertEqualObjects(notification.oldValue, [NSNumber numberWithBool:NO], @"Expected old value to be NO, got %@", notification.oldValue);
            STAssertEqualObjects(notification.newValue, [NSNumber numberWithBool:YES], @"Expected new value to be YES, got %@", notification.newValue);
            STAssertFalse(notification.isPrior, @"Expected prior flag to be NO, it wasn't.");
        }];
        target.toggle = YES;
        [observation remove];
    
        observation = [observer observeTarget:target keyPath:@"toggle"
                                options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                                block:
        ^ (MAKVONotification *notification) {
            STAssertEqualObjects(notification.keyPath, @"toggle", @"Expected keyPath of \"toggle\", got \"%@\"", notification.keyPath);
            STAssertEqualObjects(notification.observer, observer, @"Expected observer to be %@, got %@", observer, notification.observer);
            STAssertEqualObjects(notification.target, target, @"Expected target to be %@, got %@", target, notification.target);
            STAssertEquals(notification.kind, (NSKeyValueChange)NSKeyValueChangeSetting, @"Expected kind to be \"setting\", got %lu", notification.kind);
            STAssertNil(notification.oldValue, @"Expected old value to be nil, got %@", notification.oldValue);
            STAssertEqualObjects(notification.newValue, [NSNumber numberWithBool:YES], @"Expected new value to be YES, got %@", notification.newValue);
            STAssertFalse(notification.isPrior, @"Expected prior flag to be NO, it wasn't.");
        }];
//		[observation remove];	// unnecessary!
    }
}

- (void)testSingleObserverMultipleTargets
{
    #define STAssertTriggers(t1, t2, t3, t4, t5)	\
        STAssert ## t1(trigger1, @"First trigger misfire");	\
        STAssert ## t2(trigger2, @"Second trigger misfire");	\
        STAssert ## t3(trigger3, @"Third trigger misfire");	\
        STAssert ## t4(observer->_triggered, @"Fourth trigger misfire");	\
        STAssert ## t5(observer->_triggered2, @"Fifth trigger misfire");	\
        do { trigger1 = NO; trigger2 = NO; trigger3 = NO; observer->_triggered = NO; observer->_triggered2 = NO; } while (0)
    
    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target1 = [[TestObject alloc] init], *target2 = [[TestObject alloc] init],
                                *target3 = [[TestObject alloc] init], *target4 = [[TestObject alloc] init];
        id<MAKVOObservation>	observation1 = nil, observation2 = nil, observation3 = nil, observation4 = nil, observation5 = nil;
        BOOL					__block trigger1 = NO, __block trigger2 = NO, __block trigger3 = NO;
        
        @autoreleasepool
        {
            observation1 = [[observer observeTarget:target1 keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger1 = YES; }] retain];
            observation2 = [[observer observeTarget:target2 keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger2 = YES; }] retain];
            observation3 = [[observer observeTarget:target3 keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger3 = YES; }] retain];
            observation4 = [[observer observeTarget:target4 keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
            observation5 = [[observer observeTarget:target4 keyPath:@"toggle" selector:@selector(observePath2:object:change:info:)
                                      userInfo:@"test" options:0] retain];
        }
        [observation1 autorelease];
        [observation2 autorelease];
        [observation3 autorelease];
        [observation4 autorelease];
        [observation5 autorelease];
        
        @autoreleasepool
        {
            target1.toggle = YES;
            target2.toggle = YES;
            target3.toggle = YES;
            target4.toggle = YES;
        }
        STAssertTriggers(True, True, True, True, True);
        
        [observation1 remove];
        @autoreleasepool { target1.toggle = NO; }
        STAssertTriggers(False, False, False, False, False);
        
        [target2 release];
        STAssertFalse(observation2.isValid, @"Second observation didn't automatically deregister");
        
        @autoreleasepool { target3.toggle = NO; }
        STAssertTriggers(False, False, True, False, False);
        
        [observer stopObserving:target4 keyPath:@"toggle" selector:@selector(observePath:object:change:info:)];
        @autoreleasepool { target4.toggle = NO; }
        STAssertFalse(observation4.isValid, @"Fourth observation wasn't deregistered");
        STAssertTriggers(False, False, False, False, True);

        @autoreleasepool
        {
            observation4 = [[observer observeTarget:target4 keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
        }
        [observation4 autorelease];
        
        [observer stopObserving:target4 keyPath:@"toggle"];
        STAssertFalse(observation4.isValid, @"Fourth observation wasn't deregistered again");
        STAssertFalse(observation5.isValid, @"Fifth observation wasn't deregistered");

        @autoreleasepool
        {
            observation4 = [[observer observeTarget:target4 keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
            observation5 = [[observer observeTarget:target4 keyPath:@"toggle" selector:@selector(observePath2:object:change:info:)
                                      userInfo:@"test" options:0] retain];
        }
        [observation4 autorelease];
        [observation5 autorelease];
        
        [observer stopObservingAllTargets];
        STAssertFalse(observation3.isValid, @"Third observation wasn't deregistered");
        STAssertFalse(observation4.isValid, @"Fourth observation wasn't deregistered");
        STAssertFalse(observation5.isValid, @"Fifth observation wasn't deregistered");
        
        [target1 release];
        [target3 release];
        [target4 release];
    }
#undef STAssertTriggers
}

- (void)testSingleTargetMultipleObservers
{
    #define STAssertTriggers(t1, t2, t3, t4, t5)	\
        STAssert ## t1(trigger1, @"First trigger misfire");	\
        STAssert ## t2(trigger2, @"Second trigger misfire");	\
        STAssert ## t3(trigger3, @"Third trigger misfire");	\
        STAssert ## t4(observer4->_triggered, @"Fourth trigger misfire");	\
        STAssert ## t5(observer5->_triggered, @"Fifth trigger misfire");	\
        do { trigger1 = NO; trigger2 = NO; trigger3 = NO; observer4->_triggered = NO; observer5->_triggered = NO; } while (0)
    
    @autoreleasepool
    {
        TestObserver			*observer1 = [[TestObserver alloc] init], *observer2 = [[TestObserver alloc] init],
                                *observer3 = [[TestObserver alloc] init], *observer4 = [[TestObserver alloc] init],
                                *observer5 = [[TestObserver alloc] init];
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        id<MAKVOObservation>	observation1 = nil, observation2 = nil, observation3 = nil, observation4 = nil, observation5 = nil;
        BOOL					__block trigger1 = NO, __block trigger2 = NO, __block trigger3 = NO;
        
        @autoreleasepool
        {
            observation1 = [[observer1 observeTarget:target keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger1 = YES; }] retain];
            observation2 = [[observer2 observeTarget:target keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger2 = YES; }] retain];
            observation3 = [[observer3 observeTarget:target keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger3 = YES; }] retain];
            observation4 = [[observer4 observeTarget:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
            observation5 = [[observer5 observeTarget:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
        }
        [observation1 autorelease];
        [observation2 autorelease];
        [observation3 autorelease];
        [observation4 autorelease];
        [observation5 autorelease];
        
        @autoreleasepool { target.toggle = YES; }
        STAssertTriggers(True, True, True, True, True);
        
        [observation1 remove];
        @autoreleasepool { target.toggle = NO; }
        STAssertTriggers(False, True, True, True, True);
        
        [observer2 release];
        STAssertFalse(observation2.isValid, @"Second observation didn't automatically deregister");
        
        [observer4 stopObserving:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)];
        @autoreleasepool { target.toggle = NO; }
        STAssertFalse(observation4.isValid, @"Fourth observation wasn't deregistered");
        STAssertTriggers(False, False, True, False, True);

        [observer5 stopObserving:target keyPath:@"toggle"];
        STAssertFalse(observation5.isValid, @"Fifth observation wasn't deregistered");
        
        @autoreleasepool
        {
            observation4 = [[observer4 observeTarget:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
            observation5 = [[observer5 observeTarget:target keyPath:@"toggle" selector:@selector(observePath:object:change:info:)
                                      userInfo:@"test" options:0] retain];
        }
        [observation4 autorelease];
        [observation5 autorelease];
        
        [target removeAllObservers];
        STAssertFalse(observation3.isValid, @"Third observation wasn't deregistered");
        STAssertFalse(observation4.isValid, @"Fourth observation wasn't deregistered");
        STAssertFalse(observation5.isValid, @"Fifth observation wasn't deregistered");
        
        [observer1 release];
        [observer3 release];
        [observer4 release];
        [observer5 release];
    }
    #undef STAssertTriggers
}

- (void)testKeyPathProtocol
{
    #define STAssertTriggers(t1, t2)	\
        STAssert ## t1(trigger1, @"First trigger misfire");	\
        STAssert ## t2(trigger2, @"Second trigger misfire");	\
        do { trigger1 = NO; trigger2 = NO; } while (0)
    #define TestKeyPath(paths)	do {	\
        observation = [observer observeTarget:target keyPath:(paths) options:0 block:notificationBlock];	\
        target.toggle = YES;	\
        STAssertTriggers(True, False);	\
        target.toggle2 = YES;	\
        STAssertTriggers(False, True);	\
        [observation remove];	\
    } while (0)

    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target = [[[TestObject alloc] init] autorelease];
        TestKeyPaths			*keyPaths = [[[TestKeyPaths alloc] init] autorelease];
        id<MAKVOObservation>	observation = nil;
        BOOL					__block trigger1 = NO, __block trigger2 = NO;
        void					(^notificationBlock)(MAKVONotification *) = ^ (MAKVONotification *notification) {
            if ([notification.keyPath isEqualToString:@"toggle"])
                trigger1 = YES;
            else if ([notification.keyPath isEqualToString:@"toggle2"])
                trigger2 = YES;
        };
        
        TestKeyPath(([NSArray arrayWithObjects:@"toggle", @"toggle2", nil]));
        TestKeyPath(([NSSet setWithObjects:@"toggle", @"toggle2", nil]));
        TestKeyPath(([NSOrderedSet orderedSetWithObjects:@"toggle", @"toggle2", nil]));
        TestKeyPath(keyPaths);
    }
    #undef TestKeyPath
    #undef STAssertTriggers
}

- (void)testArrayTarget
{
    #define STAssertTriggers(t1, t2)	\
        STAssert ## t1(trigger1, @"First trigger misfire");	\
        STAssert ## t2(trigger2, @"Second trigger misfire");	\
        do { trigger1 = NO; trigger2 = NO; } while (0)

    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target1 = [[[TestObject alloc] init] autorelease], *target2 = [[[TestObject alloc] init] autorelease];
        NSArray					*targetArray = [NSArray arrayWithObjects:target1, target2, nil];
        id<MAKVOObservation>	observation = nil;
        BOOL					__block trigger1 = NO, __block trigger2 = NO;
        void					(^notificationBlock)(MAKVONotification *) = ^ (MAKVONotification *notification) {
            if (notification.target == target1)
                trigger1 = YES;
            else if (notification.target == target2)
                trigger2 = YES;
        };
        
        observation = [observer observeTarget:targetArray keyPath:@"toggle" options:0 block:notificationBlock];
        target1.toggle = YES;
        STAssertTriggers(True, False);
        target2.toggle = YES;
        STAssertTriggers(False, True);
        target1.toggle = YES;
        target2.toggle = YES;
        STAssertTriggers(True, True);

        [observation remove];
        target1.toggle = YES;
        target2.toggle = YES;
        STAssertTriggers(False, False);
    }
}

- (void)testArrayTargetAutoDeregistration
{
    @autoreleasepool
    {
        TestObserver			*observer = [[[TestObserver alloc] init] autorelease];
        TestObject				*target1 = [[[TestObject alloc] init] autorelease], *target2 = [[[TestObject alloc] init] autorelease];
        NSArray					*targetArray = [[NSArray alloc] initWithObjects:target1, target2, nil];
        id<MAKVOObservation>	observation = nil;
        
        @autoreleasepool
        {
            observation = [[observer observeTarget:targetArray keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { }] retain];
        }
        [observation autorelease];
        [targetArray release];
        STAssertFalse(observation.isValid, @"Array target wasn't auto-deregistered on deallocation");
    }
}

- (void)testSelfObservation
{
    @autoreleasepool
    {
        TestObject					*object1 = [[[TestObject alloc] init] autorelease];
        id<MAKVOObservation>		observation = nil;
        BOOL						__block trigger = NO;
        
        observation = [object1 observeTarget:object1 keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { trigger = !trigger; }];
        object1.toggle = YES;
        STAssertTrue(trigger, @"Trigger didn't fire or fired too many times.");
        [observation remove];
        trigger = NO;
        object1.toggle = NO;
        STAssertFalse(observation.isValid, @"Observation didn't go invalid.");
        STAssertFalse(trigger, @"Trigger fired but shouldn't have.");
        
        @autoreleasepool
        {
            TestObject				*object2 = [[[TestObject alloc] init] autorelease];
            
            observation = [[object2 addObserver:object2 keyPath:@"toggle" options:0 block:^ (MAKVONotification *notification) { }] retain];
        }
        [observation autorelease];
        STAssertFalse(observation.isValid, @"Observation didn't automatically deregister.");
    }
}

- (void)testMultipleDeallocSwizzleInHierarchy
{
    NSMutableArray *observations = [NSMutableArray array];
    @autoreleasepool {
        TestObject *object = [[[TestObject alloc] init] autorelease];
        DeallocTesterSuperclass *observer1 = [[[DeallocTesterSuperclass alloc] init] autorelease];
        DeallocTesterSubclass *observer2 = [[[DeallocTesterSubclass alloc] init] autorelease];
        
        [observations addObject: [object addObserver:observer1 keyPath:@"self" options:0
                                                block:^(MAKVONotification *notification) {}]];
        [observations addObject: [object addObserver:observer2 keyPath:@"self" options:0
                                                block:^(MAKVONotification *notification) {}]];
    }
}

@end
