#import <UIKit/UIKit.h>

@interface FileManagerViewController : UIViewController

// Initialize with a specific directory path
- (instancetype)initWithPath:(NSString *)path;

// Initialize with a specific directory path and a source file path for move/copy operations
- (instancetype)initWithPath:(NSString *)path sourceFilePath:(NSString *)sourceFilePath operationType:(NSInteger)operationType;

// Initialize with a specific directory path and multiple source file paths for move/copy operations
- (instancetype)initWithPath:(NSString *)path sourceFilePaths:(NSArray<NSString *> *)sourceFilePaths operationType:(NSInteger)operationType;

@end 