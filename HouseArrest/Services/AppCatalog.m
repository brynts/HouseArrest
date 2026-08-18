#import "AppCatalog.h"
#import "bad_query.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSMutableString *gProbe;

static void probeReset(void) {
    gProbe = [NSMutableString string];
}

static void probe(NSString *fmt, ...) {
    if (!gProbe) gProbe = [NSMutableString string];
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [gProbe appendFormat:@"%@\n", line];
}

NSString *HACatalogLastProbe(void) {
    return gProbe.length ? [gProbe copy] : @"(no probe)";
}

static NSString *stringValue(id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return nil;
}

static NSString *pathValue(id value) {
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    return stringValue(value);
}

static void addProxy(NSMutableDictionary *result, id app) {
    NSString *bundleID = nil;
    SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
    if ([app respondsToSelector:bidSel]) {
        bundleID = stringValue(((id (*)(id, SEL))objc_msgSend)(app, bidSel));
    }
    if (!bundleID.length) return;

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

static NSDictionary *appsFromWorkspace(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    probe(@"LSApplicationWorkspace class=%@", workspaceClass ?: @"nil");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSel]) return result;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
    probe(@"defaultWorkspace=%@", workspace ?: @"nil");
    if (!workspace) return result;

    for (NSString *selName in @[ @"allInstalledApplications", @"allApplications", @"installedApplications" ]) {
        SEL sel = NSSelectorFromString(selName);
        BOOL responds = [workspace respondsToSelector:sel];
        if (!responds) {
            probe(@"LS %@ responds=NO", selName);
            continue;
        }
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, sel);
        NSUInteger count = [candidate isKindOfClass:[NSArray class]] ? [candidate count] : 0;
        probe(@"LS %@ class=%@ count=%lu", selName, NSStringFromClass([candidate class]) ?: @"nil", (unsigned long)count);
        if (count == 0) continue;
        for (id app in candidate) addProxy(result, app);
        if (result.count) return result;
    }

    SEL enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:block:");
    if ([workspace respondsToSelector:enumSel]) {
        for (NSUInteger type = 0; type <= 1; type++) {
            NSMutableArray *collected = [NSMutableArray array];
            void (^block)(id) = ^(id app) { if (app) [collected addObject:app]; };
            ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(workspace, enumSel, type, block);
            probe(@"LS enumerate type=%lu count=%lu", (unsigned long)type, (unsigned long)collected.count);
            for (id app in collected) addProxy(result, app);
        }
    } else {
        probe(@"LS enumerateApplicationsOfType:block: responds=NO");
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
    probe(@"MobileInstallationLookup=%p handle=%p", lookup, handle);
    if (!lookup) return result;

    NSArray *optionSets = @[
        @{ @"ApplicationType": @"User" },
        @{ @"ApplicationType": @"Any" },
        @{},
    ];
    for (NSDictionary *options in optionSets) {
        NSDictionary *apps = ((NSDictionary *(*)(NSDictionary *, void *))lookup)(options, NULL);
        probe(@"MI lookup options=%@ class=%@ count=%lu",
              options[@"ApplicationType"] ?: @"empty",
              NSStringFromClass([apps class]) ?: @"nil",
              (unsigned long)([apps isKindOfClass:[NSDictionary class]] ? apps.count : 0));
        if (![apps isKindOfClass:[NSDictionary class]] || apps.count == 0) continue;
        [apps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSDictionary class]]) return;
            NSDictionary *info = obj;
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = stringValue(info[@"CFBundleDisplayName"])
                ?: stringValue(info[@"CFBundleName"])
                ?: (NSString *)key;
            NSString *container = pathValue(info[@"Container"]) ?: pathValue(info[@"ContainerPath"]);
            if (container.length) entry[@"container"] = container;
            result[key] = entry;
        }];
        if (result.count) break;
    }
    return result;
}

static BOOL isUUIDFolder(NSString *name) {
    if (name.length != 36) return NO;
    return [name characterAtIndex:8] == '-' &&
        [name characterAtIndex:13] == '-' &&
        [name characterAtIndex:18] == '-' &&
        [name characterAtIndex:23] == '-';
}

static NSDictionary *plistAfterGrant(NSString *container) {
    char buf[1024];
    if (![container getCString:buf maxLength:sizeof(buf) encoding:NSUTF8StringEncoding]) return nil;
    int64_t handle = bad_query(buf, true, NULL, false);
    NSString *meta = [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:meta];
    if (handle >= 0) bad_query_release(handle);
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

static NSDictionary *appsFromContainerWalk(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    char root[] = "/var/mobile/Containers/Data/Application";
    char *listed = bad_query_list(root, 400000);
    if (!listed) {
        char alt[] = "/private/var/mobile/Containers/Data/Application";
        listed = bad_query_list(alt, 400000);
        probe(@"bad_query_list private-var fallback ptr=%p", listed);
    }
    if (!listed) {
        probe(@"bad_query_list returned NULL");
        return result;
    }

    NSArray *lines = [[NSString stringWithUTF8String:listed] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    free(listed);
    probe(@"bad_query_list entries=%lu sample=%@",
          (unsigned long)lines.count,
          lines.firstObject.length ? lines.firstObject : @"(empty)");

    NSInteger grantOK = 0, grantMeta = 0, skipped = 0;
    for (NSString *raw in lines) {
        @autoreleasepool {
            NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!line.length) continue;
            NSString *leaf = line.lastPathComponent;
            if (!isUUIDFolder(leaf)) {
                skipped++;
                continue;
            }
            NSString *container = line;
            if (![container hasPrefix:@"/"]) {
                container = [@(root) stringByAppendingPathComponent:leaf];
            }
            if ([container hasPrefix:@"/var/"] && ![container hasPrefix:@"/private/"]) {
                NSString *priv = [@"/private" stringByAppendingString:container];
                NSDictionary *plist = plistAfterGrant(priv) ?: plistAfterGrant(container);
                if (!plist) continue;
                grantOK++;
                NSString *bundleID = stringValue(plist[@"MCMMetadataIdentifier"]);
                if (!bundleID.length) continue;
                grantMeta++;
                NSString *display = bundleID;
                id info = plist[@"MCMMetadataInfo"];
                if ([info isKindOfClass:[NSDictionary class]]) {
                    NSString *n = stringValue(info[@"CFBundleDisplayName"]) ?: stringValue(info[@"CFBundleName"]);
                    if (n.length) display = n;
                }
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"name"] = display;
                entry[@"container"] = priv;
                result[bundleID] = entry;
                continue;
            }
            NSDictionary *plist = plistAfterGrant(container);
            if (!plist) continue;
            grantOK++;
            NSString *bundleID = stringValue(plist[@"MCMMetadataIdentifier"]);
            if (!bundleID.length) continue;
            grantMeta++;
            NSString *display = bundleID;
            id info = plist[@"MCMMetadataInfo"];
            if ([info isKindOfClass:[NSDictionary class]]) {
                NSString *n = stringValue(info[@"CFBundleDisplayName"]) ?: stringValue(info[@"CFBundleName"]);
                if (n.length) display = n;
            }
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = display;
            entry[@"container"] = container;
            result[bundleID] = entry;
        }
    }
    probe(@"walk skippedNonUUID=%ld grantedReadable=%ld withBundleID=%ld apps=%lu",
          (long)skipped, (long)grantOK, (long)grantMeta, (unsigned long)result.count);
    return result;
}

NSDictionary<NSString *, NSDictionary *> *HAInstalledAppCatalog(void) {
    probeReset();
    probe(@"host bundle=%@", NSBundle.mainBundle.bundleIdentifier ?: @"nil");
    NSDictionary *workspace = appsFromWorkspace();
    probe(@"workspace count=%lu", (unsigned long)workspace.count);
    if (workspace.count > 0) return workspace;
    NSDictionary *mi = appsFromMobileInstallation();
    probe(@"mobileinstall count=%lu", (unsigned long)mi.count);
    if (mi.count > 0) return mi;
    return appsFromContainerWalk();
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
