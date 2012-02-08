//
//  MAKVONotificationCenter.h
//  MAKVONotificationCenter
//
//  Created by Michael Ash on 10/15/08.
//

#import <Foundation/Foundation.h>

/******************************************************************************/
enum
{
	// These constants are technically unsafe to use, as Apple could add options
	//	with identical values in the future. I'm hoping the highest possible
	//	bits are high enough for them not to bother with before a point in time
	//	where it won't matter anymore. Only 32 bits are used, as the definition
	//	of NSUInteger is 32 bits on iOS.
	
	// Pass this flag to disable automatic de-registration of observers at
	//	dealloc-time of observer or target. This avoids some swizzling hackery
	//	on the observer and target objects.
	// WARNING: Because of the way MAKVONotificationCenter works, you will NOT
	//	get a standard KVO exception when you forget to unregister observations;
	//	you'll just crash at some point! Fixing this so that the exception is
	//	thrown anyway would render this option moot, as its point is to allow
	//	you to disable the runtime hackery that makes automatic de-registration
	//	work.
	MAKeyValueObservingOptionUnregisterManually		= 0x80000000,
	
	// Pass this flag to avoid the passing of MAKVONotification objects to
	//	block-based observer callbacks. This saves an object allocation, at the
	//	expense of making all the information in the object inaccessible. nil
	//	will be passed as the parameter to the block. This is really only useful
	//	if you expect to be getting a LOT of observations and you're worried
	//	about memory usage and/or microbenchmark speed.
	MAKeyValueObservingOptionNoInformation			= 0x40000000,
};

/******************************************************************************/
// An object representing a (potentially) active observation.
@protocol MAKVOObservation <NSObject>

@required
- (BOOL)isValid;	// returns NO if the observation has been deregistered by any means
- (void)remove;

@end

/******************************************************************************/
// An object adopting this protocol can be passed as a key path. Strings,
//	arrays, sets, and ordered sets automatically get this support.
@protocol MAKVOKeyPath <NSObject>

@required
- (NSSet *)ma_keyPathsAsSetOfStrings;

@end

/******************************************************************************/
@interface MAKVONotification : NSObject

@property(copy,readonly)	NSString			*keyPath;
@property(weak,readonly)	id					observer, target;
@property(assign,readonly)	NSKeyValueChange	kind;
@property(strong,readonly)	id					oldValue, newValue;
@property(strong,readonly)	NSIndexSet			*indexes;
@property(assign,readonly)	BOOL				isPrior;

@end

/******************************************************************************/
// As with Apple's KVO, observer and target are NOT retained.
// An observation object (as returned by an -addObserver: method) will be
//	rendered invalid when either the observer or target are deallocated. If you
//	hold on to a strong reference past that point, the object will still be
//	valid, but will no longer be useful for anything (however, passing it to
//	-removeObservation is harmless). It is strongly recommended that
//	references to observation objects be weak (or nonexistent), as this will
//	make automatic deregistration 100% leak-free.
// -addObserver:keyPath:selector:userInfo:options: is exactly identical to
//	-observeTarget:keyPath:selector:userInfo:options: with the sender and target
//	switched; which you use is a matter of preference.
@interface NSObject (MAKVONotification)

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

#if NS_BLOCKS_AVAILABLE

- (id<MAKVOObservation>)addObserver:(id)observer
							keyPath:(id<MAKVOKeyPath>)keyPath
							options:(NSKeyValueObservingOptions)options
							  block:(void (^)(MAKVONotification *notification))block;

- (id<MAKVOObservation>)observeTarget:(id)target
							  keyPath:(id<MAKVOKeyPath>)keyPath
							  options:(NSKeyValueObservingOptions)options
								block:(void (^)(MAKVONotification *notification))block;

#endif

- (void)removeAllObservers;
- (void)stopObservingAllTargets;

- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath;
- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath;

- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;
- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;

@end

/******************************************************************************/
@interface MAKVONotificationCenter : NSObject

+ (id)defaultCenter;

// selector should have the following signature:
//	- (void)observeValueForKeyPath:(NSString *)keyPath
//						  ofObject:(id)target
//							change:(NSDictionary *)change
//						  userInfo:(id)userInfo;

// If target is an NSArray, every object in the collection will be observed,
//	per -addObserver:toObjectsAtIndexes:.
- (id<MAKVOObservation>)addObserver:(id)observer
							 object:(id)target
							keyPath:(id<MAKVOKeyPath>)keyPath
						   selector:(SEL)selector
						   userInfo:(id)userInfo
							options:(NSKeyValueObservingOptions)options;

#if NS_BLOCKS_AVAILABLE

- (id<MAKVOObservation>)addObserver:(id)observer
							 object:(id)target
							keyPath:(id<MAKVOKeyPath>)keyPath
							options:(NSKeyValueObservingOptions)options
							  block:(void (^)(MAKVONotification *notification))block;

#endif

// remove all observations registered by observer on target with keypath using
//	selector. nil for any parameter is a wildcard. One of observer or target
//	must be non-nil. The only way to deregister a specific block is to
//	remove its particular MAKVOObservation.
- (void)removeObserver:(id)observer object:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector;

// remove specific registered observation
- (void)removeObservation:(id<MAKVOObservation>)observation;

@end

/******************************************************************************/
// Declarations to make the basic objects work as key paths; these are
//	technically private, but need to be publically visible or the compiler will
//	complain.
@interface NSString (MAKeyPath) <MAKVOKeyPath>
@end
@interface NSArray (MAKeyPath) <MAKVOKeyPath>
@end
@interface NSSet (MAKeyPath) <MAKVOKeyPath>
@end
@interface NSOrderedSet (MAKeyPath) <MAKVOKeyPath>
@end
