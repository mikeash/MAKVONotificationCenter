//
//  MAKVONotificationCenter.m
//  MAKVONotificationCenter
//
//  Created by Michael Ash on 10/15/08.
//

#import "MAKVONotificationCenter.h"

#import <libkern/OSAtomic.h>
#import <objc/message.h>


@interface _MAKVONotificationHelper : NSObject
{
	id			_observer;
	SEL			_selector;
	id			_userInfo;
	
	id			_target;
	NSString*	_keyPath;
}

- (id)initWithObserver:(id)observer object:(id)target keyPath:(NSString *)keyPath selector:(SEL)selector userInfo: (id)userInfo options: (NSKeyValueObservingOptions)options;
- (void)deregister;

@end

@implementation _MAKVONotificationHelper

static char MAKVONotificationHelperMagicContext;

- (id)initWithObserver:(id)observer object:(id)target keyPath:(NSString *)keyPath selector:(SEL)selector userInfo: (id)userInfo options: (NSKeyValueObservingOptions)options
{
	if((self = [self init]))
	{
		_observer = observer;
		_selector = selector;
		_userInfo = [userInfo retain];
		
		_target = target;
		_keyPath = [keyPath retain];
		
		[target addObserver:self
				 forKeyPath:keyPath
					options:options
					context:&MAKVONotificationHelperMagicContext];
	}
	return self;
}

- (void)dealloc
{
	[_userInfo release];
	[_keyPath release];
	[super dealloc];
}

#pragma mark -

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(context == &MAKVONotificationHelperMagicContext)
	{
		// we only ever sign up for one notification per object, so if we got here
		// then we *know* that the key path and object are what we want
		((void (*)(id, SEL, NSString *, id, NSDictionary *, id))objc_msgSend)(_observer, _selector, keyPath, object, change, _userInfo);
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)deregister
{
	[_target removeObserver:self forKeyPath:_keyPath];
}

@end


@implementation MAKVONotificationCenter

+ (id)defaultCenter
{
	static MAKVONotificationCenter *center = nil;
	if(!center)
	{
		// do a bit of clever atomic setting to make this thread safe
		// if two threads try to set simultaneously, one will fail
		// and the other will set things up so that the failing thread
		// gets the shared center
		MAKVONotificationCenter *newCenter = [[self alloc] init];
		if(!OSAtomicCompareAndSwapPtrBarrier(nil, newCenter, (void *)&center))
			[newCenter release];
	}
	return center;
}

- (id)init
{
	if((self = [super init]))
	{
		_observerHelpers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_observerHelpers release];
	[super dealloc];
}

#pragma mark -

- (id)_dictionaryKeyForObserver:(id)observer object:(id)target keyPath:(NSString *)keyPath selector:(SEL)selector
{
	return [NSString stringWithFormat:@"%p:%p:%@:%p", observer, target, keyPath, selector];
}

- (void)addObserver:(id)observer object:(id)target keyPath:(NSString *)keyPath selector:(SEL)selector userInfo: (id)userInfo options: (NSKeyValueObservingOptions)options
{
	_MAKVONotificationHelper *helper = [[_MAKVONotificationHelper alloc] initWithObserver:observer object:target keyPath:keyPath selector:selector userInfo:userInfo options:options];
	id key = [self _dictionaryKeyForObserver:observer object:target keyPath:keyPath selector:selector];
	@synchronized(self)
	{
		[_observerHelpers setObject:helper forKey:key];
	}
	[helper release];
}

- (void)removeObserver:(id)observer object:(id)target keyPath:(NSString *)keyPath selector:(SEL)selector
{
	id key = [self _dictionaryKeyForObserver:observer object:target keyPath:keyPath selector:selector];
	_MAKVONotificationHelper *helper = nil;
	@synchronized(self)
	{
		helper = [[_observerHelpers objectForKey:key] retain];
		[_observerHelpers removeObjectForKey:key];
	}
	[helper deregister];
	[helper release];
}

@end

@implementation NSObject (MAKVONotification)

- (void)addObserver:(id)observer forKeyPath:(NSString *)keyPath selector:(SEL)selector userInfo:(id)userInfo options:(NSKeyValueObservingOptions)options
{
	[[MAKVONotificationCenter defaultCenter] addObserver:observer object:self keyPath:keyPath selector:selector userInfo:userInfo options:options];
}

- (void)removeObserver:(id)observer keyPath:(NSString *)keyPath selector:(SEL)selector
{
	[[MAKVONotificationCenter defaultCenter] removeObserver:observer object:self keyPath:keyPath selector:selector];
}

@end
