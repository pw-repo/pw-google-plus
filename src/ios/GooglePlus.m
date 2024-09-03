#import "AppDelegate.h"
#import "objc/runtime.h"
#import <Cordova/CDV.h>
#import <GoogleSignIn/GoogleSignIn.h>

@interface GooglePlus : CDVPlugin {
  // Member variables go here.
}

@property (nonatomic, assign) BOOL isSigningIn;
@property (nonatomic, copy) NSString* callbackId;

@end

@implementation GooglePlus

- (void)pluginInitialize
{
    NSLog(@"GooglePlus pluginInitizalize");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:CDVPluginHandleOpenURLNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLWithAppSourceAndAnnotation:) name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void)handleOpenURL:(NSNotification*)notification
{
    // no need to handle this handler, we dont have an sourceApplication here, which is required by GIDSignIn handleURL
}

- (void)handleOpenURLWithAppSourceAndAnnotation:(NSNotification*)notification
{
    NSMutableDictionary * options = [notification object];

    NSURL* url = options[@"url"];

    NSString* possibleReversedClientId = [url.absoluteString componentsSeparatedByString:@":"].firstObject;

    if ([possibleReversedClientId isEqualToString:self.getreversedClientId] && self.isSigningIn) {
        self.isSigningIn = NO;
        [GIDSignIn.sharedInstance handleURL:url];
    }
}

// If this returns false, you better not call the login function because of likely app rejection by Apple,
// see https://code.google.com/p/google-plus-platform/issues/detail?id=900
// Update: should be fine since we use the GoogleSignIn framework instead of the GooglePlus framework
- (void) isAvailable:(CDVInvokedUrlCommand*)command {
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];

    [self configureSignInWithOptions:options];

    NSString *hint = options[@"hint"];
    NSArray* scopes = options[@"scopes"];

    [GIDSignIn.sharedInstance signInWithPresentingViewController:presentingViewController hint:hint additionalScopes:scopes completion:^(GIDSignInResult * _Nullable signInResult, NSError * _Nullable error) {
       [self handleCompletion:user withError:error];
    }]
}

- (void) trySilentLogin:(CDVInvokedUrlCommand*)command {
     _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];

    [self configureSignInWithOptions:options];

    [GIDSignIn.sharedInstance restorePreviousSignInWithCompletion:^(GIDGoogleUser * user, NSError * _Nullable error) {
      [self handleCompletion:user serverAuthCode:nil withError:error];
    }]
}

- (void)configureSignInWithOptions:(NSDictionary *)options {
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];

    GIDConfiguration* config = [[GIDConfiguration alloc] initWithClientID:clientId serverClientID:options[@"webClientId"] hostedDomain:options[@"hostedDomain"]];

    GIDSignIn.sharedInstance.configuration = config;
}

- (void)handleCompletion:(GIDSignInResult * _Nullable)signInResult withError:(NSError * _Nullable)error {
    
    [self handleCompletion:signInResult.user serverAuthCode:signInResult.serverAuthCode withError:error];
}

- (void)handleCompletion:(GIDGoogleUser * _Nullable)user serverAuthCode:(nullable NSString*)serverAuthCode withError:(NSError * _Nullable)error {
    if (error) {
         CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
         [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
    } else {
        if (user) {
            NSURL *imageURL = user.profile.hasImage ? [user.profile imageURLWithDimension:120] : nil;

            NSDictionary *result = @{
                             @"userId": user.userID,
                             @"email": user.profile.email,
                             @"idToken": user.idToken.tokenString,
                             @"displayName": user.profile.name? : [NSNull null],
                             @"givenName": user.profile.givenName ? : [NSNull null],
                             @"familyName": user.profile.familyName? : [NSNull null],
                             @"imageUrl": imageURL ? imageURL.absoluteString : [NSNull null],
                             @"serverAuthCode": nil
                             };

            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        } else {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"User is null"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        }
    }
}

- (NSString*) reverseUrlScheme:(NSString*)scheme {
  NSArray* originalArray = [scheme componentsSeparatedByString:@"."];
  NSArray* reversedArray = [[originalArray reverseObjectEnumerator] allObjects];
  NSString* reversedString = [reversedArray componentsJoinedByString:@"."];
  return reversedString;
}

- (NSString*) getreversedClientId {
  NSArray* URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];

  if (URLTypes != nil) {
    for (NSDictionary* dict in URLTypes) {
      NSString *urlName = dict[@"CFBundleURLName"];
      if ([urlName isEqualToString:@"REVERSED_CLIENT_ID"]) {
        NSArray* URLSchemes = dict[@"CFBundleURLSchemes"];
        if (URLSchemes != nil) {
          return URLSchemes[0];
        }
      }
    }
  }
  return nil;
}

- (void) logout:(CDVInvokedUrlCommand*)command {
  [GIDSignIn.sharedInstance signOut];
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
  [GIDSignIn.sharedInstance disconnectWithCompletion:^(NSError * _Nullable error) {
    if (error) {
      CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
    }
    else {
      CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
  }];

}

- (void) share_unused:(CDVInvokedUrlCommand*)command {
  // for a rainy day.. see for a (limited) example https://github.com/vleango/GooglePlus-PhoneGap-iOS/blob/master/src/ios/GPlus.m
}

#pragma mark - GIDSignInDelegate
- (void)signIn:(GIDSignIn *)signIn presentViewController:(UIViewController *)viewController {
    self.isSigningIn = YES;
    [self.viewController presentViewController:viewController animated:YES completion:nil];
}

- (void)signIn:(GIDSignIn *)signIn dismissViewController:(UIViewController *)viewController {
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

@end
