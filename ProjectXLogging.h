#ifndef PROJECTX_LOGGING_H
#define PROJECTX_LOGGING_H

#import <Foundation/Foundation.h>

/**
 * Custom logging function for ProjectX
 * Writes logs to both NSLog and a file
 */
void PXLog(NSString *format, ...);

/**
 * Error logging with recovery attempt
 * @param error The error to log
 * @param context Context description where the error occurred
 */
void PXLogError(NSError *error, NSString *context);

#endif /* PROJECTX_LOGGING_H */ 