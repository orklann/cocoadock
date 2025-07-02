#import <Cocoa/Cocoa.h>
#include "cocoadock.h"

VALUE rb_mCocoadock;
VALUE rb_mCocoadockClass;

VALUE cocoadock_initialize(VALUE self);
VALUE cocoadock_add_app_to_dock(VALUE self, VALUE path);
VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path);

void addAppToDock(NSString *appPath) {
    // Ensure app path is absolute and URL encoded
    NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSString *urlString = [appURL absoluteString]; // e.g. "file:///Applications/Safari.app"

    NSString *dockEntry = [NSString stringWithFormat:
        @"'{\"tile-data\"={\"file-data\"={\"_CFURLString\"=\"%@\";\"_CFURLStringType\"=15;};};\"tile-type\"=\"file-tile\";}'",
        urlString];

    NSString *defaultsWrite = [NSString stringWithFormat:
        @"defaults write com.apple.dock persistent-apps -array-add %@", dockEntry];

    system([defaultsWrite UTF8String]);
    system("killall Dock");

    NSLog(@"Added %@ to Dock", appPath);
}

void removeAppFromDock(NSString *appPath) {
    // Read current persistent apps from Dock preferences
    NSString *plistPath = [@"~/Library/Preferences/com.apple.dock.plist" stringByExpandingTildeInPath];
    NSMutableDictionary *dockPlist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!dockPlist) {
        NSLog(@"Failed to read Dock plist.");
        return;
    }

    NSMutableArray *persistentApps = [dockPlist[@"persistent-apps"] mutableCopy];
    if (!persistentApps) {
        NSLog(@"No persistent apps found in Dock plist.");
        return;
    }

    // Normalize input app path (resolve symlinks, remove trailing slash)
    NSString *normalizedAppPath = [[NSURL fileURLWithPath:appPath] path];

    // Filter out any entries whose file URL path matches the app path
    NSIndexSet *indexesToRemove = [persistentApps indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        NSDictionary *tileData = entry[@"tile-data"];
        NSDictionary *fileData = tileData[@"file-data"];
        NSString *urlString = fileData[@"_CFURLString"];
        if (urlString) {
            NSURL *url = [NSURL URLWithString:urlString];
            NSString *entryPath = [url path];
            return [entryPath isEqualToString:normalizedAppPath];
        }
        return NO;
    }];

    if (indexesToRemove.count == 0) {
        NSLog(@"App not found in Dock.");
        return;
    }

    [persistentApps removeObjectsAtIndexes:indexesToRemove];
    dockPlist[@"persistent-apps"] = persistentApps;

    // Save updated plist back to file
    BOOL success = [dockPlist writeToFile:plistPath atomically:YES];
    if (!success) {
        NSLog(@"Failed to write updated Dock plist.");
        return;
    }

    // Restart the Dock to apply changes
    system("killall Dock");

    NSLog(@"Removed %@ from Dock.", appPath);
}

RUBY_FUNC_EXPORTED void
Init_cocoadock(void)
{
  rb_mCocoadock = rb_define_module("CocoaDock");
  rb_mCocoadockClass = rb_define_class_under(rb_mCocoadock, "CocoaDock", rb_cObject);
  rb_define_method(rb_mCocoadockClass, "initialize", cocoadock_initialize, 0);
  rb_define_method(rb_mCocoadockClass, "add_app", cocoadock_add_app_to_dock, 1);
  rb_define_method(rb_mCocoadockClass, "remove_app", cocoadock_remove_app_from_dock, 1);
}

VALUE cocoadock_initialize(VALUE self) {
  rb_iv_set(self, "@var", rb_hash_new());
  return self;
}

VALUE cocoadock_add_app_to_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    NSString *appPath = [[NSString alloc] initWithCString:c_app_path encoding:NSUTF8StringEncoding];
    addAppToDock(appPath);
}

VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    NSString *appPath = [[NSString alloc] initWithCString:c_app_path encoding:NSUTF8StringEncoding];
    removeAppFromDock(appPath);
}
