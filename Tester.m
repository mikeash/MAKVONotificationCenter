//
//  Tester.m
//  MAKVONotificationCenter
//
//  Created by Michael Ash on 10/15/08.
//

#import "Tester.h"

#import "MAKVONotificationCenter.h"


@implementation Tester

- (void)testDictionary
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								 @"foo", @"key",
								 nil];
	
	[dict addObserver:self forKeyPath:@"key" selector:@selector(_observeValueForKeyPath:ofObject:change:userInfo:) userInfo:@"userInfo" options:NSKeyValueObservingOptionNew];
	
	[dict setObject:@"bar" forKey:@"key"];
	NSAssert(_triggered, @"failed to trigger");
	
	[dict removeObserver:self keyPath:@"key" selector:@selector(_observeValueForKeyPath:ofObject:change:userInfo:)];
	
	_triggered = NO;
	[dict setObject:@"foo" forKey:@"key"];
	NSAssert(!_triggered, @"triggered after deregistering");
}

- (void)_observeValueForKeyPath:(NSString *)keyPath ofObject:(id)target change:(NSDictionary *)change userInfo:(id)userInfo
{
	NSLog(@"%s: %@ changed %@ dictionary %@ info %@", __func__, target, keyPath, change, userInfo);
	_triggered = YES;
}

@end

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	Tester *tester = [[Tester alloc] init];
	[tester testDictionary];
	
	[pool release];
	return 0;
}

