#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Name / container path for every installed app (LaunchServices first).
NSDictionary<NSString *, NSDictionary *> *HAInstalledAppCatalog(void);
UIImage * _Nullable HAIconForBundleID(NSString *bundleID);

NS_ASSUME_NONNULL_END
