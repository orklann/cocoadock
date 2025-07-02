#import <Cocoa/Cocoa.h>
#include "cocoadock.h"

VALUE rb_mCocoadock;
VALUE rb_mCocoadockClass;

VALUE cocoadock_initialize(VALUE self);
VALUE cocoadock_add_app_to_dock(VALUE self, VALUE path);
VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path);

void addAppToDock(const char *app_path) {
    NSString *appPath = [[NSString alloc] initWithCString:app_path encoding:NSUTF8StringEncoding];

    // Convert to file URL with percent escapes
    NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSString *urlString = appURL.absoluteString;

    // Now form the Dock entry
    NSString *dockEntry = [NSString stringWithFormat:
        @"'<dict>"
         "<key>tile-data</key><dict>"
           "<key>file-data</key><dict>"
             "<key>_CFURLString</key><string>%@</string>"
             "<key>_CFURLStringType</key><integer>15</integer>"
           "</dict>"
         "</dict>"
       "</dict>'", urlString];

    NSString *command = [NSString stringWithFormat:
        @"defaults write com.apple.dock persistent-apps -array-add %@ && killall Dock", dockEntry];

    // Execute the command
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sh";
    task.arguments = @[@"-c", command];
    [task launch];
}

void removeAppFromDock(const char* app_path) {
    NSString *appPath = [[NSString alloc] initWithCString:app_path encoding:NSUTF8StringEncoding];
    NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSString *urlString = appURL.absoluteString;

    // Step 1: Export current Dock preferences
    NSString *exportPlistCmd = @"defaults export com.apple.dock - > /tmp/com.apple.dock.plist";
    system([exportPlistCmd UTF8String]);

    // Step 2: Load the plist
    NSMutableDictionary *dockPlist = [NSMutableDictionary dictionaryWithContentsOfFile:@"/tmp/com.apple.dock.plist"];
    NSMutableArray *persistentApps = [dockPlist[@"persistent-apps"] mutableCopy];
    if (!persistentApps) return;

    // Step 3: Filter out the app by matching its _CFURLString
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *entry in persistentApps) {
        NSDictionary *tileData = entry[@"tile-data"];
        NSDictionary *fileData = tileData[@"file-data"];
        NSString *entryURL = fileData[@"_CFURLString"];
        if (![entryURL isEqualToString:urlString]) {
            [filtered addObject:entry];
        }
    }

    // Step 4: Save updated plist and re-import
    dockPlist[@"persistent-apps"] = filtered;
    [dockPlist writeToFile:@"/tmp/com.apple.dock.plist" atomically:YES];

    NSString *importCmd = @"defaults import com.apple.dock /tmp/com.apple.dock.plist";
    system([importCmd UTF8String]);

    // Step 5: Restart Dock
    system("killall Dock");
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
    //NSString *appPath = [[NSString alloc] initWithCString:c_app_path encoding:NSUTF8StringEncoding];
    addAppToDock(c_app_path);
}

VALUE cocoadock_remove_app_from_dock(VALUE self, VALUE path) {
    const char *c_app_path = StringValueCStr(path);
    //NSString *appPath = [[NSString alloc] initWithCString:c_app_path encoding:NSUTF8StringEncoding];
    removeAppFromDock(c_app_path);
}
