#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, NSDictionary *> *HAInstalledAppCatalog(void);
NSDictionary *HAPresentationForBundleID(NSString *bundleID);
UIImage * _Nullable HAIconForBundleID(NSString *bundleID);
NSString *HACatalogLastProbe(void);

NS_ASSUME_NONNULL_END
