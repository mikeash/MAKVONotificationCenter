//
//  MAKVONotificationCenter.m
//  MAKVONotificationCenter
//
//  Created by Michael Ash on 10/15/08.
//

#import "MAKVONotificationCenter.h"
#import <libkern/OSAtomic.h>
#import <objc/message.h>
#import <objc/runtime.h>

/******************************************************************************/
static const char			* const MAKVONotificationCenter_HelpersKey = "MAKVONotificationCenter_helpers";

/******************************************************************************/
@interface MAKVONotification ()
{
	NSDictionary			*change;
}

- (id)initWithObserver:(id)observer_ object:(id)target_ keyPath:(NSString *)keyPath_ change:(NSDictionary *)change_;

@property(copy,readwrite)	NSString			*keyPath;
@property(weak,readwrite)	id					observer, target;

@end

/******************************************************************************/
@implementation MAKVONotification

@synthesize keyPath, observer, target;

- (id)initWithObserver:(id)observer_ object:(id)target_ keyPath:(NSString *)keyPath_ change:(NSDictionary *)change_
{
	if ((self = [super init]))
	{
		self.observer = observer_;
		self.target = target_;
		self.keyPath = keyPath_;
		change = change_;
	}
	return self;
}

- (NSKeyValueChange)kind { return [[change objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue]; }
- (id)oldValue { return [change objectForKey:NSKeyValueChangeOldKey]; }
- (id)newValue { return [change objectForKey:NSKeyValueChangeNewKey]; }
- (NSIndexSet *)indexes { return [change objectForKey:NSKeyValueChangeIndexesKey]; }
- (BOOL)isPrior { return [[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue]; }

@end

/******************************************************************************/
@interface _MAKVONotificationHelper : NSObject <MAKVOObservation>
{
  @public		// for MAKVONotificationCenter
	id							__weak _observer;
	id							__weak _target;
	NSSet						*_keyPaths;
	NSKeyValueObservingOptions	_options;
	SEL							_selector;	// NULL for block-based
	id							_userInfo;	// block for block-based
}

- (id)initWithObserver:(id)observer object:(id)target keyPaths:(NSSet *)keyPaths
			  selector:(SEL)selector userInfo:(id)userInfo options:(NSKeyValueObservingOptions)options;
- (void)deregister;

@end

/******************************************************************************/
@implementation _MAKVONotificationHelper

static char MAKVONotificationHelperMagicContext = 0;

- (id)initWithObserver:(id)observer object:(id)target keyPaths:(NSSet *)keyPaths
			  selector:(SEL)selector userInfo:(id)userInfo options:(NSKeyValueObservingOptions)options
{
	if ((self = [self init]))
	{
		_observer = observer;
		_selector = selector;
		_userInfo = userInfo;
		_target = target;
		_keyPaths = keyPaths;
		_options = options;
		
		// Pass only Apple's options to Apple's code.
		options &= ~(MAKeyValueObservingOptionUnregisterManually | MAKeyValueObservingOptionNoInformation);
		
		for (NSString *keyPath in _keyPaths)
		{
			if ([target isKindOfClass:[NSArray class]])
			{
				[target addObserver:self toObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [target count])]
						 forKeyPath:keyPath options:options context:&MAKVONotificationHelperMagicContext];
			}
			else
				[target addObserver:self forKeyPath:keyPath options:options context:&MAKVONotificationHelperMagicContext];
		}

		NSMutableSet				*observerHelpers = objc_getAssociatedObject(_observer, MAKVONotificationCenter_HelpersKey),
									*targetHelpers = objc_getAssociatedObject(_target, MAKVONotificationCenter_HelpersKey);
		
		if (!observerHelpers)
			objc_setAssociatedObject(_observer, MAKVONotificationCenter_HelpersKey, observerHelpers = [NSMutableSet set], OBJC_ASSOCIATION_RETAIN);
		[observerHelpers addObject:self];
		if (!targetHelpers)
			objc_setAssociatedObject(_target, MAKVONotificationCenter_HelpersKey, targetHelpers = [NSMutableSet set], OBJC_ASSOCIATION_RETAIN);
		[targetHelpers addObject:self];
	}
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &MAKVONotificationHelperMagicContext)
	{
		if (!_observer || !_target)	// weak reference got nilled
		{
			[self remove];
			return;
		}
		
#if NS_BLOCKS_AVAILABLE
		if (_selector)
#endif
			((void (*)(id, SEL, NSString *, id, NSDictionary *, id))objc_msgSend)(_observer, _selector, keyPath, object, change, _userInfo);
#if NS_BLOCKS_AVAILABLE
		else
		{
			MAKVONotification		*notification = nil;

			if (!(_options & MAKeyValueObservingOptionNoInformation))
				notification = [[MAKVONotification alloc] initWithObserver:_observer object:_target keyPath:keyPath change:change];
			((void (^)(MAKVONotification *))_userInfo)(notification);
		}
#endif
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)deregister
{
	for (NSString *keyPath in _keyPaths)
		[_target removeObserver:self forKeyPath:keyPath context:&MAKVONotificationHelperMagicContext];
	
	[objc_getAssociatedObject(_observer, MAKVONotificationCenter_HelpersKey) removeObject:self];
	[objc_getAssociatedObject(_target, MAKVONotificationCenter_HelpersKey) removeObject:self];
	
	// Protect against multiple invocations
	_observer = nil;
	_target = nil;
	_keyPaths = nil;
}

- (BOOL)isValid
{
	return _observer && _target;
}

- (void)remove
{
	[self deregister];
}

- (void)dealloc
{
	[self deregister];
}

- (NSUInteger)hash
{
	// userInfo is NOT involved in hash
	return [_observer hash] ^ [_target hash] ^ [_keyPaths hash] ^ _options ^ (NSUInteger)_selector;
}

- (BOOL)isEqual:(id)object
{
	return object == self;	// Identity is the only equality.
}

@end

/******************************************************************************/
@interface MAKVONotificationCenter ()
{
	NSMutableSet			*_swizzledClasses;
}

- (void)_swizzleObjectClassIfNeeded:(id)object;

@end

@implementation MAKVONotificationCenter

+ (id)defaultCenter
{
	static MAKVONotificationCenter		*center = nil;
	static dispatch_once_t				onceToken = 0;
	
	// I really wanted to keep Mike's old way of doing this with
	//	OSAtomicCompareAndSwapPtrBarrier(); that was just cool! Unfortunately,
	//	pragmatism says always hand thread-safety off to the OS when possible as
	//	a matter of prudence, not that I can imagine the old way ever breaking.
	//	Also, this way is, while much less cool, a bit more readable.
	dispatch_once(&onceToken, ^ {
		center = [[MAKVONotificationCenter alloc] init];
	});
	return center;
}

- (id)init
{
	if ((self = [super init]))
	{
		_swizzledClasses = [[NSMutableSet alloc] init];
	}
	return self;
}

#if NS_BLOCKS_AVAILABLE

- (id<MAKVOObservation>)addObserver:(id)observer
							 object:(id)target
							keyPath:(id<MAKVOKeyPath>)keyPath
							options:(NSKeyValueObservingOptions)options
							  block:(void (^)(MAKVONotification *notification))block
{
	return [self addObserver:observer object:target keyPath:keyPath selector:NULL userInfo:[block copy] options:options];
}

#endif

- (id<MAKVOObservation>)addObserver:(id)observer
							 object:(id)target
							keyPath:(id<MAKVOKeyPath>)keyPath
						   selector:(SEL)selector
						   userInfo:(id)userInfo
							options:(NSKeyValueObservingOptions)options;
{
	NSSet						*keyPaths = [[keyPath ma_keyPathsAsSetOfStrings] copy];
	_MAKVONotificationHelper	*helper = [[_MAKVONotificationHelper alloc] initWithObserver:observer object:target keyPaths:keyPaths
																					selector:selector userInfo:userInfo options:options];
	
	// RAIAIROFT: Resource Acquisition Is Allocation, Initialization, Registration, and Other Fun Tricks.
	if (!(options & MAKeyValueObservingOptionUnregisterManually))
	{
		[self _swizzleObjectClassIfNeeded:observer];
		[self _swizzleObjectClassIfNeeded:target];
	}
	return helper;
}

- (void)removeObserver:(id)observer object:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector
{
	NSParameterAssert(observer || target);	// at least one of observer or target must be non-nil
	
	@autoreleasepool
	{
		NSMutableSet				*observerHelpers = objc_getAssociatedObject(observer, MAKVONotificationCenter_HelpersKey),
									*targetHelpers = objc_getAssociatedObject(target, MAKVONotificationCenter_HelpersKey);
		
		// Don't have to worry about set mutations, as the -unionSet: creates a new set.
		for (_MAKVONotificationHelper *helper in [targetHelpers setByAddingObjectsFromSet:observerHelpers])
		{
			if ((!observer || helper->_observer == observer) &&
				(!target || helper->_target == target) &&
				(!keyPath || [helper->_keyPaths isEqualToSet:[keyPath ma_keyPathsAsSetOfStrings]]) &&
				(!selector || helper->_selector == selector))
			{
				[helper deregister];
			}
		}
	}
}

- (void)removeObservation:(id<MAKVOObservation>)observation
{
	[observation remove];
}

static void			MAKVONotificationCenter_CustomDealloc(id self, SEL _cmd)
{
	[objc_getAssociatedObject(self, MAKVONotificationCenter_HelpersKey) removeAllObjects];

    Method			originalDealloc = class_getInstanceMethod(object_getClass(self), @selector(MAKVONotificationCenter_KVO_original_dealloc));
	
//	class_replaceMethod(object_getClass(self), NSSelectorFromString(@"dealloc"), method_getImplementation(originalDealloc), method_getTypeEncoding(originalDealloc));
NSLog(@"deallocating %@", self);
	((void (*)(id, SEL))method_getImplementation(originalDealloc))(self, _cmd);
}

- (void)_swizzleObjectClassIfNeeded:(id)object
{
	@synchronized (_swizzledClasses)
	{
		Class			class = object_getClass(object);//[object class];
		
		if ([_swizzledClasses containsObject:class])
			return;
		
	    Method			dealloc = class_getInstanceMethod(class, NSSelectorFromString(@"dealloc")/*@selector(dealloc)*/);
    
	    class_addMethod(class, @selector(MAKVONotificationCenter_KVO_original_dealloc), method_getImplementation(dealloc), method_getTypeEncoding(dealloc));
	    class_replaceMethod(class, NSSelectorFromString(@"dealloc"), (IMP)MAKVONotificationCenter_CustomDealloc, method_getTypeEncoding(dealloc));
		[_swizzledClasses addObject:class];
	}
}

@end

/******************************************************************************/
@implementation NSObject (MAKVONotification)

- (id<MAKVOObservation>)addObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector userInfo:(id)userInfo
							options:(NSKeyValueObservingOptions)options
{
	return [[MAKVONotificationCenter defaultCenter] addObserver:observer object:self keyPath:keyPath selector:selector userInfo:userInfo options:options];
}

- (id<MAKVOObservation>)observeTarget:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector userInfo:(id)userInfo
							  options:(NSKeyValueObservingOptions)options
{
	return [[MAKVONotificationCenter defaultCenter] addObserver:self object:target keyPath:keyPath selector:selector userInfo:userInfo options:options];
}

#if NS_BLOCKS_AVAILABLE

- (id<MAKVOObservation>)addObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath options:(NSKeyValueObservingOptions)options
							  block:(void (^)(MAKVONotification *notification))block
{
	return [[MAKVONotificationCenter defaultCenter] addObserver:observer object:self keyPath:keyPath options:options block:block];
}

- (id<MAKVOObservation>)observeTarget:(id)target keyPath:(id<MAKVOKeyPath>)keyPath options:(NSKeyValueObservingOptions)options
								block:(void (^)(MAKVONotification *notification))block
{
	return [[MAKVONotificationCenter defaultCenter] addObserver:self object:target keyPath:keyPath options:options block:block];
}

#endif

- (void)removeAllObservers
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:nil object:self keyPath:nil selector:NULL];
}

- (void)stopObservingAllTargets
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:self object:nil keyPath:nil selector:NULL];
}

- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:observer object:self keyPath:keyPath selector:NULL];
}

- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:self object:target keyPath:keyPath selector:NULL];
}

- (void)removeObserver:(id)observer keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:observer object:self keyPath:keyPath selector:selector];
}

- (void)stopObserving:(id)target keyPath:(id<MAKVOKeyPath>)keyPath selector:(SEL)selector
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:self object:target keyPath:keyPath selector:selector];
}

@end

/******************************************************************************/
@implementation NSString (MAKeyPath)

- (NSSet *)ma_keyPathsAsSetOfStrings
{
	return [NSSet setWithObject:self];
}

@end

@implementation NSArray (MAKeyPath)

- (NSSet *)ma_keyPathsAsSetOfStrings
{
	return [NSSet setWithArray:self];
}

@end

@implementation NSSet (MAKeyPath)

- (NSSet *)ma_keyPathsAsSetOfStrings
{
	return self;
}

@end

@implementation NSOrderedSet (MAKeyPath)

- (NSSet *)ma_keyPathsAsSetOfStrings
{
	return [self set];
}

@end
