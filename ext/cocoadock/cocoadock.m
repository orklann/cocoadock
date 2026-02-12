#import <Cocoa/Cocoa.h>
#include "cocoadock.h"

VALUE rb_mCocoadock;
VALUE rb_mCocoadockClass;

VALUE cocoadock_initialize(VALUE self);
VALUE cocoadock_is_app_to_dock(VALUE self, VALUE path);
VALUE cocoadock_add_app_to_dock(VALUE self, VALUE path);
VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path);
VALUE cocoadock_remove_others_in_dock(VALUE self);
VALUE cocoadock_remove_all_apps_in_dock(VALUE self);

NSMutableArray *LoadDockApps(void) {
    CFArrayRef persistentApps = CFPreferencesCopyAppValue(
        CFSTR("persistent-apps"),
        CFSTR("com.apple.dock")
    );

    if (!persistentApps) {
        return [NSMutableArray array];
    }

    NSMutableArray *apps =
        [(__bridge NSArray *)persistentApps mutableCopy];

    CFRelease(persistentApps);
    return apps;
}

void SaveDockApps(NSArray *apps) {
    CFPreferencesSetAppValue(
        CFSTR("persistent-apps"),
        (__bridge CFArrayRef)apps,
        CFSTR("com.apple.dock")
    );

    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));

    system("killall Dock");
}

NSMutableArray *LoadDockOthers(void) {
    CFArrayRef persistentOthers = CFPreferencesCopyAppValue(
        CFSTR("persistent-others"),
        CFSTR("com.apple.dock")
    );

    if (!persistentOthers) {
        return [NSMutableArray array];
    }

    NSMutableArray *others =
        [(__bridge NSArray *)persistentOthers mutableCopy];

    CFRelease(persistentOthers);
    return others;
}

void SaveDockOthers(NSArray *others) {
    CFPreferencesSetAppValue(
        CFSTR("persistent-others"),
        (__bridge CFArrayRef)others,
        CFSTR("com.apple.dock")
    );

    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));

    system("killall Dock");
}

BOOL RemoveAllAppsInDock(void) {

    int attempts = 0;

    while (attempts < 3) {

        NSMutableArray *apps = LoadDockApps();

        if (apps.count == 0) {
            return YES; // Already empty
        }

        [apps removeAllObjects];

        SaveDockApps(apps);

        // Give Dock time to restart & commit
        [NSThread sleepForTimeInterval:0.25];

        // Verify
        NSMutableArray *verify = LoadDockApps();
        if (verify.count == 0) {
            return YES;
        }

        attempts++;
        [NSThread sleepForTimeInterval:0.1];
    }

    return NO;
}

BOOL RemoveOthersInDock(void) {

    int attempts = 0;

    while (attempts < 3) {

        NSMutableArray *others = LoadDockOthers();

        if (others.count == 0) {
            return YES; // Already empty
        }

        [others removeAllObjects];

        SaveDockOthers(others);

        // Give Dock time to restart and commit
        [NSThread sleepForTimeInterval:0.25];

        // Verify
        NSMutableArray *verify = LoadDockOthers();
        if (verify.count == 0) {
            return YES;
        }

        attempts++;
        [NSThread sleepForTimeInterval:0.1];
    }

    return NO;
}


BOOL IsAppInDock(NSString *bundleID) {
    if (!bundleID) return NO;

    // Load Dock plist directly
    NSString *plistPath = [@"~/Library/Preferences/com.apple.dock.plist" stringByExpandingTildeInPath];
    NSDictionary *dockPlist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *persistentApps = dockPlist[@"persistent-apps"];
    if (!persistentApps) return NO;

    for (NSDictionary *item in persistentApps) {
        NSDictionary *tileData = item[@"tile-data"];
        if (!tileData) continue;

        // 1️⃣ Check bundle identifier
        NSString *appBundleID = tileData[@"bundle-identifier"];
        if ([appBundleID isEqualToString:bundleID]) {
            return YES;
        }

        // 2️⃣ Fallback: check file path
        NSDictionary *fileData = tileData[@"file-data"];
        NSString *path = fileData[@"_CFURLString"];
        if (!path) continue;

        // Handle possible URL or relative path
        if (![path hasPrefix:@"/"]) {
            NSURL *url = [NSURL URLWithString:path];
            path = url.path;
        }

        if (!path) continue;

        // Resolve symlinks
        path = [[NSURL fileURLWithPath:path] URLByResolvingSymlinksInPath].path;

        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle && [bundle.bundleIdentifier isEqualToString:bundleID]) {
            return YES;
        }
    }

    return NO;
}


NSURL *AppURLForBundleID(NSString *bundleID) {
    if (!bundleID) return nil;

    CFArrayRef urls = LSCopyApplicationURLsForBundleIdentifier(
        (__bridge CFStringRef)bundleID,
        NULL
    );

    if (!urls || CFArrayGetCount(urls) == 0) {
        if (urls) CFRelease(urls);
        return nil;
    }

    CFURLRef firstURL = CFArrayGetValueAtIndex(urls, 0);
    NSURL *appURL = (__bridge NSURL *)firstURL;

    CFRelease(urls); // release the array, not the item
    return appURL;
}

NSDictionary *DockTileForAppURL(NSURL *appURL) {
    if (!appURL) return nil;

    NSDictionary *fileData = @{
        @"_CFURLString": appURL.absoluteString,
        @"_CFURLStringType": @15
    };

    NSDictionary *tileData = @{
        @"file-data": fileData
    };

    return @{
        @"tile-type": @"file-tile",
        @"tile-data": tileData
    };
}

void AddDockAppByBundleID(NSString *bundleID) {
    CFArrayRef persistentApps = CFPreferencesCopyAppValue(
        CFSTR("persistent-apps"),
        CFSTR("com.apple.dock")
    );

    if (!persistentApps) {
        NSLog(@"Failed to read Dock preferences");
        return;
    }

    NSMutableArray *apps =
        [(__bridge NSArray *)persistentApps mutableCopy];

    if (!apps || !bundleID) return;

    NSURL *appURL = AppURLForBundleID(bundleID);
    if (!appURL) {
        NSLog(@"Could not resolve app for bundle ID %@", bundleID);
        return;
    }

    NSString *targetPath = appURL.path;

    // Prevent duplicates
    for (NSDictionary *item in apps) {
        NSDictionary *fileData = item[@"tile-data"][@"file-data"];
        NSString *urlString = fileData[@"_CFURLString"];
        if (!urlString) continue;

        NSString *path = [[NSURL URLWithString:urlString] path];
        if ([path isEqualToString:targetPath]) {
            return;
        }
    }

    NSDictionary *dockItem = DockTileForAppURL(appURL);
    if (dockItem) {
        [apps addObject:dockItem];
    }

    CFPreferencesSetAppValue(
        CFSTR("persistent-apps"),
        (__bridge CFArrayRef)apps,
        CFSTR("com.apple.dock")
    );

    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));

    CFRelease(persistentApps);
}

void RemoveDockAppByBundleID(NSString *bundleID) {
    CFArrayRef persistentApps = CFPreferencesCopyAppValue(
        CFSTR("persistent-apps"),
        CFSTR("com.apple.dock")
    );

    NSMutableArray *apps =
        [(__bridge NSArray *)persistentApps mutableCopy];

    if (!apps || !bundleID) {
        return;
    }

    for (NSInteger i = apps.count - 1; i >= 0; i--) {
        NSDictionary *item = apps[i];
        NSDictionary *tileData = item[@"tile-data"];

        NSString *dockBundleID = tileData[@"bundle-identifier"];
        if ([dockBundleID isEqualToString:bundleID]) {
            [apps removeObjectAtIndex:i];
            continue;
        }

        NSDictionary *fileData = tileData[@"file-data"];
        NSString *urlString = fileData[@"_CFURLString"];
        if (urlString) {
            NSString *path = [[NSURL URLWithString:urlString] path];
            if ([path containsString:bundleID]) {
                [apps removeObjectAtIndex:i];
            }
        }
    }

    CFPreferencesSetAppValue(
        CFSTR("persistent-apps"),
        (__bridge CFArrayRef)apps,
        CFSTR("com.apple.dock")
    );

    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));

    if (persistentApps) {
        CFRelease(persistentApps);
    }
}

BOOL isAppInDock(const char *app_path) {
    NSString *appPath = [[NSString alloc] initWithCString:app_path encoding:NSUTF8StringEncoding];
    NSBundle *bundle = [NSBundle bundleWithPath:appPath];

    if (!bundle) {
        NSLog(@"Not a valid app bundle");
        return NO;
    }
 
    NSString *bundleID = bundle.bundleIdentifier;

    return IsAppInDock(bundleID);
}

void addAppToDock(const char *app_path) {
    @autoreleasepool {
        NSString *appPath = [[NSString alloc] initWithCString:app_path encoding:NSUTF8StringEncoding];

        NSBundle *bundle = [NSBundle bundleWithPath:appPath];

        if (!bundle) {
            NSLog(@"Not a valid app bundle");
            return;
        }
     
        NSString *bundleID = bundle.bundleIdentifier;
        AddDockAppByBundleID(bundleID);
    }
}

void removeAppFromDock(const char* app_path) {
    @autoreleasepool {
        NSString *appPath = [[NSString alloc] initWithCString:app_path encoding:NSUTF8StringEncoding];

        NSBundle *bundle = [NSBundle bundleWithPath:appPath];

        if (!bundle) {
            NSLog(@"Not a valid app bundle");
            return;
        }
     
        NSString *bundleID = bundle.bundleIdentifier;
        RemoveDockAppByBundleID(bundleID);
    }
}

void removeOthersInDock () {
    RemoveOthersInDock();
}

RUBY_FUNC_EXPORTED void
Init_cocoadock(void)
{
  rb_mCocoadock = rb_define_module("CocoaDock");
  rb_mCocoadockClass = rb_define_class_under(rb_mCocoadock, "CocoaDock", rb_cObject);
  rb_define_method(rb_mCocoadockClass, "initialize", cocoadock_initialize, 0);
  rb_define_method(rb_mCocoadockClass, "add_app", cocoadock_add_app_to_dock, 1);
  rb_define_method(rb_mCocoadockClass, "app_in_dock?", cocoadock_is_app_to_dock, 1);
  rb_define_method(rb_mCocoadockClass, "remove_app", cocoadock_remove_app_from_dock, 1);
  rb_define_method(rb_mCocoadockClass, "remove_others", cocoadock_remove_others_in_dock, 0);
  rb_define_method(rb_mCocoadockClass, "remove_all", cocoadock_remove_all_apps_in_dock, 0);
}

VALUE cocoadock_initialize(VALUE self) {
  rb_iv_set(self, "@var", rb_hash_new());
  return self;
}

VALUE cocoadock_is_app_to_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    BOOL result = isAppInDock(c_app_path);
    if (result == YES) {
        return Qtrue;
    }
    return Qfalse;
}

VALUE cocoadock_add_app_to_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    addAppToDock(c_app_path);
}

VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    //NSString *appPath = [[NSString alloc] initWithCString:c_app_path encoding:NSUTF8StringEncoding];
    removeAppFromDock(c_app_path);
}

VALUE cocoadock_remove_others_in_dock(VALUE self) {
    removeOthersInDock();
}

VALUE cocoadock_remove_all_apps_in_dock(VALUE self) {
    RemoveAllAppsInDock();
}
