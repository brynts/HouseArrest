#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, NSDictionary *> *HAInstalledAppCatalog(void);
UIImage * _Nullable HAIconForBundleID(NSString *bundleID);
NSString *HACatalogLastProbe(void);

NS_ASSUME_NONNULL_END
