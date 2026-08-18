#import "AppCatalog.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *stringValue(id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return nil;
}

static NSString *pathValue(id value) {
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    return stringValue(value);
}

static NSDictionary *appsFromWorkspace(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSel]) return result;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
    if (!workspace) return result;

    NSArray *apps = nil;
    for (NSString *selName in @[ @"allInstalledApplications", @"allApplications" ]) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, sel);
        if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) {
            apps = candidate;
            break;
        }
    }
    if (!apps.count) return result;

    for (id app in apps) {
        @autoreleasepool {
            NSString *bundleID = nil;
            SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
            if ([app respondsToSelector:bidSel]) {
                bundleID = stringValue(((id (*)(id, SEL))objc_msgSend)(app, bidSel));
            }
            if (!bundleID.length) continue;

            NSString *name = bundleID;
            SEL nameSel = NSSelectorFromString(@"localizedName");
            if ([app respondsToSelector:nameSel]) {
                NSString *localized = stringValue(((id (*)(id, SEL))objc_msgSend)(app, nameSel));
                if (localized.length) name = localized;
            }

            NSString *container = nil;
            for (NSString *selName in @[ @"dataContainerURL", @"containerURL" ]) {
                SEL sel = NSSelectorFromString(selName);
                if (![app respondsToSelector:sel]) continue;
                container = pathValue(((id (*)(id, SEL))objc_msgSend)(app, sel));
                if (container.length) break;
            }

            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name;
            if (container.length) entry[@"container"] = container;
            result[bundleID] = entry;
        }
    }
    return result;
}

static NSDictionary *appsFromMobileInstallation(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation",
        RTLD_LAZY | RTLD_LOCAL
    );
    void *lookup = dlsym(RTLD_DEFAULT, "MobileInstallationLookup");
    if (!lookup && handle) lookup = dlsym(handle, "MobileInstallationLookup");
    if (!lookup) return result;

    NSDictionary *apps = nil;
    NSArray *optionSets = @[
        @{ @"ApplicationType": @"User" },
        @{ @"ApplicationType": @"Any" },
        @{},
    ];
    for (NSDictionary *options in optionSets) {
        apps = ((NSDictionary *(*)(NSDictionary *, void *))lookup)(options, NULL);
        if ([apps isKindOfClass:[NSDictionary class]] && apps.count > 0) break;
    }
    if (![apps isKindOfClass:[NSDictionary class]]) return result;

    [apps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSDictionary class]]) return;
        NSDictionary *info = obj;
        NSString *name = stringValue(info[@"CFBundleDisplayName"])
            ?: stringValue(info[@"CFBundleName"])
            ?: (NSString *)key;
        NSString *container = pathValue(info[@"Container"])
            ?: pathValue(info[@"ContainerPath"]);
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"name"] = name;
        if (container.length) entry[@"container"] = container;
        result[key] = entry;
    }];
    return result;
}

NSDictionary<NSString *, NSDictionary *> *HAInstalledAppCatalog(void) {
    NSDictionary *workspace = appsFromWorkspace();
    if (workspace.count > 0) return workspace;
    return appsFromMobileInstallation();
}

static NSData *iconDataFromProxy(id proxy) {
    SEL iconSel = NSSelectorFromString(@"iconDataForVariant:");
    if (![proxy respondsToSelector:iconSel]) return nil;
    const int variants[] = { 2, 0, 1, 3, 4, 5, 15 };
    for (size_t i = 0; i < sizeof(variants) / sizeof(variants[0]); i++) {
        id data = ((id (*)(id, SEL, int))objc_msgSend)(proxy, iconSel, variants[i]);
        if ([data isKindOfClass:[NSData class]] && [data length] > 0) return data;
    }
    return nil;
}

UIImage *HAIconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 256; });
    UIImage *cached = [cache objectForKey:bundleID];
    if (cached) return cached;

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:sel]) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, sel, bundleID);
    if (!proxy) return nil;
    NSData *data = iconDataFromProxy(proxy);
    if (!data) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (image) [cache setObject:image forKey:bundleID];
    return image;
}
