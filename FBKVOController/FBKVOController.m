/**
 Copyright (c) 2014-present, Facebook, Inc.
 All rights reserved.
 
 This source code is licensed under the BSD-style license found in the
 LICENSE file in the root directory of this source tree. An additional grant
 of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBKVOController.h"

#import <libkern/OSAtomic.h>
#import <objc/message.h>

#if !__has_feature( objc_arc )
    #error This file must be compiled with ARC. Convert your project to ARC or specify the -fobjc-arc flag.
#endif

#pragma mark Utilities

static NSString* describe_option( NSKeyValueObservingOptions _Option )
    {
    switch ( _Option )
        {
        case NSKeyValueObservingOptionNew:
            {
            return @"NSKeyValueObservingOptionNew";
            } break;

        case NSKeyValueObservingOptionOld:
            {
            return @"NSKeyValueObservingOptionOld";
            } break;

        case NSKeyValueObservingOptionInitial:
            {
            return @"NSKeyValueObservingOptionInitial";
            } break;

        case NSKeyValueObservingOptionPrior:
            {
            return @"NSKeyValueObservingOptionPrior";
            } break;

        default:
            {
            NSCAssert( NO, @"unexpected option %tu", _Option );
            } break;
        }

    return nil;
    }

static void append_option_description( NSMutableString* _Desc, NSUInteger _Option )
    {
    if ( 0 == _Desc.length )
        [ _Desc appendString: describe_option( _Option ) ];
    else
        [ _Desc appendString: @"|" ];

    [ _Desc appendString: describe_option( _Option ) ];
    }

static NSUInteger enumerate_flags( NSUInteger* ptrFlags )
    {
    NSCAssert( ptrFlags, @"expected ptrFlags" );
    if ( !ptrFlags )
        return 0;
  
    NSUInteger flags = *ptrFlags;
    if ( !flags )
        return 0;

  
    NSUInteger flag = 1 << __builtin_ctzl( flags );
    flags &= ~flag;
    *ptrFlags = flags;

    return flag;
    }

static NSString* describe_options( NSKeyValueObservingOptions options )
    {
    NSMutableString* s = [ NSMutableString string ];
    NSUInteger option;

    while ( 0 != ( option = enumerate_flags( &options ) ) )
        append_option_description( s, option );

    return s;
    }

#pragma mark _FBKVOInfo class
/**
 @abstract The key-value observation info.
 @discussion Object equality is only used within the scope of a controller instance. Safely omit controller from equality definition.
 */
@interface _FBKVOInfo : NSObject
@end

@implementation _FBKVOInfo
    {
@public
    __weak FBKVOController*     _controller;
    NSString*                   _keyPath;
    NSKeyValueObservingOptions  _options;
    FBKVONotificationBlock      _block;
    SEL                         _action;
    void*                       _context;
    }

- ( instancetype ) initWithController: ( FBKVOController* )_Controller
                              keyPath: ( NSString* )_KeyPath
                              options: ( NSKeyValueObservingOptions )_Options
                                block: ( FBKVONotificationBlock )_Block
                               action: ( SEL )_Action
                              context: ( void* )_Context
    {
    if ( self = [ super init ] )
        {
        _controller = _Controller;
        _block = [ _Block copy ];
        _keyPath = [ _KeyPath copy ];
        _options = _Options;
        _action = _Action;
        _context = _Context;
        }

    return self;
    }

- ( instancetype ) initWithController: ( FBKVOController* )_Controller
                              keyPath: ( NSString* )_KeyPath
                              options: ( NSKeyValueObservingOptions )_Options
                                block: ( FBKVONotificationBlock )_Block
    {
    return [ self initWithController: _Controller
                             keyPath: _KeyPath
                             options: _Options
                               block: _Block
                              action: NULL
                             context: NULL ];
    }

- ( instancetype ) initWithController: ( FBKVOController* )_Controller
                              keyPath: ( NSString* )_KeyPath
                              options: ( NSKeyValueObservingOptions )_Options
                               action: ( SEL )_Action
    {
    return [ self initWithController: _Controller
                             keyPath: _KeyPath
                             options: _Options
                               block: NULL
                              action: _Action
                             context: NULL ];
    }

- ( instancetype ) initWithController: ( FBKVOController* )_Controller
                              keyPath: ( NSString* )_KeyPath
                              options: ( NSKeyValueObservingOptions )_Options
                              context: ( void* )_Context
    {
    return [ self initWithController: _Controller
                             keyPath: _KeyPath
                             options: _Options
                               block: NULL
                              action: NULL
                             context: _Context ];
    }

- ( instancetype ) initWithController: ( FBKVOController* )_Controller
                              keyPath: ( NSString* )_KeyPath
    {
    return [ self initWithController: _Controller
                             keyPath: _KeyPath
                             options: 0
                               block: NULL
                              action: NULL
                             context: NULL ];
    }

- ( NSUInteger ) hash
    {
    return [ _keyPath hash ];
    }

- ( BOOL ) isEqual: ( id )_Object
    {
    if ( !_Object )
        return NO;

    if ( self == _Object)
        return YES;

    if ( ![ _Object isKindOfClass: [ self class ] ] )
        return NO;

    return [ _keyPath isEqualToString: ( ( _FBKVOInfo* )_Object )->_keyPath ];
    }

- ( NSString* ) debugDescription
    {
    NSMutableString* desc = [ NSMutableString stringWithFormat: @"<%@: %p   keyPath: %@"
                                                              , NSStringFromClass( [ self class ] )
                                                              , self
                                                              , _keyPath ];
    if ( 0 != _options )
        [ desc appendFormat:@" options: %@", describe_options( _options ) ];

    if ( _action )
        [ desc appendFormat: @" action: %@", NSStringFromSelector( _action ) ];

    if ( _context )
        [ desc appendFormat: @" context: %p", _context ];

    if ( _block )
        [ desc appendFormat: @" block: %p", _block ];

    [ desc appendString: @">" ];
    return desc;
    }

@end // _FBKVOInfo class

#pragma mark _FBKVOSharedController class
/**
 @abstract The shared KVO controller instance.
 @discussion Acts as a receptionist, receiving and forwarding KVO notifications.
 */
@interface _FBKVOSharedController : NSObject

/** A shared instance that never deallocates. */
+ ( instancetype ) sharedController;

/** observe an object, info pair */
- ( void ) observe: ( id )_Object
              info: ( _FBKVOInfo* )_Info;

/** unobserve an object, info pair */
- ( void ) unobserve: ( id )_Object
                info: ( _FBKVOInfo* )_Info;

/** unobserve an object with a set of infos */
- ( void ) unobserve: ( id )_Object
               infos: ( NSSet* )_Infos;
@end

@implementation _FBKVOSharedController
    {
    NSHashTable*    _infos;
    OSSpinLock      _lock;
    }

+ ( instancetype ) sharedController
    {
    static _FBKVOSharedController* _controller = nil;

    static dispatch_once_t onceToken;
    dispatch_once( &onceToken
     , ^{
        _controller = [ [ _FBKVOSharedController alloc ] init ];
        } );

    return _controller;
    }

- ( instancetype ) init
    {
    if ( self = [ super init ] )
        {
        NSHashTable* infos = [ NSHashTable alloc ];
    #ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
        _infos = [ infos initWithOptions: NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                capacity: 0 ];
    #elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
        if ( [ NSHashTable respondsToSelector: @selector( weakObjectsHashTable ) ] )
            {
            _infos = [ infos initWithOptions: NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                    capacity: 0 ];
            }
        else
            {
    // silence deprecated warnings
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            _infos = [ infos initWithOptions: NSPointerFunctionsZeroingWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                    capacity: 0 ];
    #pragma clang diagnostic pop
            }
    #endif
        _lock = OS_SPINLOCK_INIT;
        }

    return self;
    }

- ( NSString* ) debugDescription
    {
    NSMutableString* desc = [ NSMutableString stringWithFormat: @"<%@: %p", NSStringFromClass( [ self class ] ), self ];
  
    // lock
    OSSpinLockLock( &_lock );
  
    NSMutableArray* infoDescriptions = [ NSMutableArray arrayWithCapacity: _infos.count ];
    for ( _FBKVOInfo* info in _infos )
        [ infoDescriptions addObject: info.debugDescription ];
  
    [ desc appendFormat: @" contexts: %@", infoDescriptions ];
  
    // unlock
    OSSpinLockUnlock( &_lock );
  
    [ desc appendString: @">" ];
    return desc;
    }

- ( void ) observe: ( id )_Object
              info: ( _FBKVOInfo* )_Info
    {
    if ( !_Info )
        return;
  
    // register info
    OSSpinLockLock( &_lock );
        [ _infos addObject: _Info ];
    OSSpinLockUnlock( &_lock );
  
    // add observer
    [ _Object addObserver: self
               forKeyPath: _Info->_keyPath
                  options: _Info->_options
                  context: ( void* )_Info ];
    }

- ( void ) unobserve: ( id )_Object
                info: ( _FBKVOInfo* )_Info
    {
    if ( !_Info )
        return;
  
    // unregister info
    OSSpinLockLock( &_lock );
        [ _infos removeObject: _Info ];
    OSSpinLockUnlock( &_lock );
  
    // remove observer
    [ _Object removeObserver: self
                  forKeyPath: _Info->_keyPath
                     context: ( void* )_Info ];
    }

- ( void ) unobserve: ( id )_Object
               infos: ( NSSet* )_Infos
    {
    if ( 0 == _Infos.count )
        return;
  
    // unregister info
    OSSpinLockLock( &_lock );
        for ( _FBKVOInfo* info in _Infos )
            [ _infos removeObject: info ];
    OSSpinLockUnlock( &_lock );
  
    // remove observer
    for ( _FBKVOInfo* info in _Infos )
        {
        [ _Object removeObserver: self
                      forKeyPath: info->_keyPath
                         context: ( void* )info ];
        }
    }

- ( void ) observeValueForKeyPath: ( NSString* )_KeyPath
                         ofObject: ( id )_Object
                           change: ( NSDictionary* )_Change
                          context: ( void* )_Context
    {
    NSAssert( _Context, @"missing context keyPath:%@ object:%@ change:%@", _KeyPath, _Object, _Change );
  
    _FBKVOInfo* info;

    // lookup context in registered infos, taking out a strong reference only if it exists
    OSSpinLockLock( &_lock );
        info = [ _infos member: ( __bridge id )_Context ];
    OSSpinLockUnlock( &_lock );
  
    if ( info )
        {
        // take strong reference to controller
        FBKVOController* controller = info->_controller;
        if ( controller )
            {
            // take strong reference to observer
            id observer = controller.observer;
            if ( observer )
                {
                // dispatch custom block or action, fall back to default action
                if ( info->_block )
                    info->_block( observer, _Object, _Change );
                else if ( info->_action )
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [ observer performSelector: info->_action withObject: _Change withObject: _Object ];
                #pragma clang diagnostic pop
                else // To deal with observer's own
                    [ observer observeValueForKeyPath: _KeyPath ofObject: _Object change: _Change context: info->_context ];
                }
            }
        }
    }

@end // _FBKVOSharedController class

#pragma mark FBKVOController class
@implementation FBKVOController
    {
    NSMapTable* _objectInfosMap;
    OSSpinLock  _lock;
    }

#pragma mark Lifecycle
+ ( instancetype ) controllerWithObserver: ( id )_Observer
    {
    return [ [ self alloc ] initWithObserver: _Observer ];
    }

- ( instancetype ) initWithObserver: ( id )_Observer
                     retainObserved: ( BOOL )_RetainObserved
    {
    if ( self = [ super init ] )
        {
        _observer = _Observer;
        
        NSPointerFunctionsOptions keyOptions = _RetainObserved ? ( NSMapTableStrongMemory | NSMapTableObjectPointerPersonality )
                                                               : ( NSMapTableWeakMemory | NSMapTableObjectPointerPersonality );

        _objectInfosMap = [ [ NSMapTable alloc ] initWithKeyOptions: keyOptions
                                                       valueOptions: NSMapTableStrongMemory | NSMapTableObjectPointerPersonality
                                                           capacity: 0 ];
        _lock = OS_SPINLOCK_INIT;
        }

    return self;
    }

- ( instancetype ) initWithObserver: ( id )_Observer
    {
    return [ self initWithObserver: _Observer
                    retainObserved: YES ];
    }

- ( void ) dealloc
    {
    [ self unobserveAll ];
    }

#pragma mark Properties
- ( NSString* ) debugDescription
    {
    NSMutableString* desc = [ NSMutableString stringWithFormat: @"<%@: %p", NSStringFromClass( [ self class ] ), self ];
    [ desc appendFormat: @"     observer: <%@: %p>", NSStringFromClass( [ _observer class ] ), _observer ];
  
    // lock
    OSSpinLockLock( &_lock );
  
    if ( 0 != _objectInfosMap.count )
        [ desc appendString: @"\n  " ];
  
    for ( id object in _objectInfosMap )
        {
        NSMutableSet* infos = [ _objectInfosMap objectForKey: object ];
        NSMutableArray* infoDescriptions = [ NSMutableArray arrayWithCapacity: infos.count ];

        [ infos enumerateObjectsUsingBlock:
            ^( _FBKVOInfo* _Info, BOOL* _Stop )
                {
                [ infoDescriptions addObject: _Info.debugDescription ];
                } ];

        [ desc appendFormat: @"%@ -> %@", object, infoDescriptions ];
        }
  
    // unlock
    OSSpinLockUnlock( &_lock );
  
    [ desc appendString: @">" ];
    return desc;
    }

#pragma mark Internal Utilities
- ( void ) _observe: ( id ) _Object
               info: ( _FBKVOInfo* )_Info
    {
    // lock
    OSSpinLockLock( &_lock );
  
    NSMutableSet* infos = [ _objectInfosMap objectForKey: _Object ];
  
    // check for info existence
    _FBKVOInfo* existingInfo = [ infos member: _Info ];
    if ( existingInfo )
        {
        NSLog( @"observation info already exists %@", existingInfo );
    
        // unlock and return
        OSSpinLockUnlock( &_lock );
        return;
        }
  
    // lazilly create set of infos
    if ( !infos )
        {
        infos = [ NSMutableSet set ];
        [ _objectInfosMap setObject: infos forKey: _Object ];
        }
  
    // add info and oberve
    [ infos addObject: _Info ];
  
    // unlock prior to callout
    OSSpinLockUnlock( &_lock );
  
    [ [ _FBKVOSharedController sharedController ] observe: _Object info: _Info ];
    }

- (void)_unobserve:(id)object info:(_FBKVOInfo *)info
{
  // lock
  OSSpinLockLock(&_lock);
  
  // get observation infos
  NSMutableSet *infos = [_objectInfosMap objectForKey:object];
  
  // lookup registered info instance
  _FBKVOInfo *registeredInfo = [infos member:info];
  
  if (nil != registeredInfo) {
    [infos removeObject:registeredInfo];
    
    // remove no longer used infos
    if (0 == infos.count) {
      [_objectInfosMap removeObjectForKey:object];
    }
  }
  
  // unlock
  OSSpinLockUnlock(&_lock);
  
  // unobserve
  [[_FBKVOSharedController sharedController] unobserve:object info:registeredInfo];
}

- (void)_unobserve:(id)object
{
  // lock
  OSSpinLockLock(&_lock);
  
  NSMutableSet *infos = [_objectInfosMap objectForKey:object];
  
  // remove infos
  [_objectInfosMap removeObjectForKey:object];
  
  // unlock
  OSSpinLockUnlock(&_lock);
  
  // unobserve
  [[_FBKVOSharedController sharedController] unobserve:object infos:infos];
}

- (void)_unobserveAll
{
  // lock
  OSSpinLockLock(&_lock);
  
  NSMapTable *objectInfoMaps = [_objectInfosMap copy];
  
  // clear table and map
  [_objectInfosMap removeAllObjects];
  
  // unlock
  OSSpinLockUnlock(&_lock);
  
  _FBKVOSharedController *shareController = [_FBKVOSharedController sharedController];
  
  for (id object in objectInfoMaps) {
    // unobserve each registered object and infos
    NSSet *infos = [objectInfoMaps objectForKey:object];
    [shareController unobserve:object infos:infos];
  }
}

#pragma mark API
- ( void ) observe: ( id )_Object
           keyPath: ( NSString* )_KeyPath
           options: ( NSKeyValueObservingOptions )_Options
             block: ( FBKVONotificationBlock )_Block
    {
    NSAssert( ( 0 != _KeyPath.length ) && _Block
            , @"missing required parameters observe: %@     keyPath: %@ block: %p"
            , _Object, _KeyPath, _Block
            );

    if ( !_Object || 0 == _KeyPath.length || !_Block )
        return;
  
    // create info
    _FBKVOInfo* info = [ [ _FBKVOInfo alloc ] initWithController: self
                                                         keyPath: _KeyPath
                                                         options: _Options
                                                           block: _Block ];
    // observe object with info
    [ self _observe: _Object info: info ];
    }

- ( void )observe: ( id )_Object
         keyPaths: ( NSArray* )_KeyPaths
          options: ( NSKeyValueObservingOptions )_Options
            block: ( FBKVONotificationBlock )_Block
    {
    NSAssert( 0 != _KeyPaths.count && _Block
            , @"missing required parameters observe: %@ keyPath: %@ block: %p"
            , _Object, _KeyPaths, _Block
            );

    if ( !_Object || 0 == _KeyPaths.count || !_Block )
        return;
  
    for ( NSString* keyPath in _KeyPaths )
        {
        [ self observe: _Object
               keyPath: keyPath
               options: _Options
                 block: _Block ];
        }
    }

- ( void )observe: ( id )_Object
          keyPath: ( NSString* )_KeyPath
          options: ( NSKeyValueObservingOptions )_Options
           action: ( SEL )_Action
    {
    NSAssert( 0 != _KeyPath.length && _Action
            , @"missing required parameters observe: %@ keyPath: %@ action: %@"
            , _Object, _KeyPath, NSStringFromSelector( _Action )
            );

    NSAssert( [ _observer respondsToSelector: _Action ]
            , @"%@ does not respond to %@"
            , _observer, NSStringFromSelector( _Action )
            );

    if ( !_Object || 0 == _KeyPath.length || !_Action )
        return;
  
    // create info
    _FBKVOInfo* info = [ [ _FBKVOInfo alloc ] initWithController: self
                                                         keyPath: _KeyPath
                                                         options: _Options
                                                          action: _Action ];
    // observe object with info
    [ self _observe: _Object info: info ];
    }

- (void)observe:(id)object keyPaths:(NSArray *)keyPaths options:(NSKeyValueObservingOptions)options action:(SEL)action
{
  NSAssert(0 != keyPaths.count && NULL != action, @"missing required parameters observe:%@ keyPath:%@ action:%@", object, keyPaths, NSStringFromSelector(action));
  NSAssert([_observer respondsToSelector:action], @"%@ does not respond to %@", _observer, NSStringFromSelector(action));
  if (nil == object || 0 == keyPaths.count || NULL == action) {
    return;
  }
  
  for (NSString *keyPath in keyPaths)
  {
    [self observe:object keyPath:keyPath options:options action:action];
  }
}

- (void)observe:(id)object keyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
  NSAssert(0 != keyPath.length, @"missing required parameters observe:%@ keyPath:%@", object, keyPath);
  if (nil == object || 0 == keyPath.length) {
    return;
  }
  
  // create info
  _FBKVOInfo *info = [[_FBKVOInfo alloc] initWithController:self keyPath:keyPath options:options context:context];
  
  // observe object with info
  [self _observe:object info:info];
}

- (void)observe:(id)object keyPaths:(NSArray *)keyPaths options:(NSKeyValueObservingOptions)options context:(void *)context
{
  NSAssert(0 != keyPaths.count, @"missing required parameters observe:%@ keyPath:%@", object, keyPaths);
  if (nil == object || 0 == keyPaths.count) {
    return;
  }
  
  for (NSString *keyPath in keyPaths)
  {
    [self observe:object keyPath:keyPath options:options context:context];
  }
}

- (void)unobserve:(id)object keyPath:(NSString *)keyPath
{
  // create representative info
  _FBKVOInfo *info = [[_FBKVOInfo alloc] initWithController:self keyPath:keyPath];
  
  // unobserve object property
  [self _unobserve:object info:info];
}

- ( void ) unobserve: ( id )_Object
    {
    if ( !_Object )
        return;
  
    [ self _unobserve: _Object ];
    }

- ( void ) unobserveAll
    {
    [ self _unobserveAll ];
    }

@end
