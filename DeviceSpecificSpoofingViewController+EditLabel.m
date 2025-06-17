#import "DeviceSpecificSpoofingViewController.h"
#import <objc/runtime.h>
#import "IdentifierManager.h"

@implementation DeviceSpecificSpoofingViewController (EditLabel)

- (void)editIdentifierLabelTapped:(UITapGestureRecognizer *)sender {
    NSString *key = objc_getAssociatedObject(sender, "identifierKey");
    if (!key) return;
    
    // Set the title based on the key
    NSString *title = key;  // Default to the key itself
    
    NSString *currentValue = [[IdentifierManager sharedManager] currentValueForIdentifier:key] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", title]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    // Configure the text field based on the key type
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentValue;
        textField.placeholder = [NSString stringWithFormat:@"Enter %@", title];
        
        // Set appropriate keyboard type based on the identifier
        if ([key isEqualToString:@"DeviceTheme"]) {
            // For DeviceTheme, set up a picker instead with Light/Dark options
            // But for now, just use ASCII capable keyboard
            textField.keyboardType = UIKeyboardTypeASCIICapable;
            textField.placeholder = @"Enter Light or Dark";
        } else if ([key isEqualToString:@"DeviceModel"]) {
            textField.keyboardType = UIKeyboardTypeASCIICapable;
            textField.placeholder = @"Enter model identifier (e.g., iPhone15,2)";
        } else {
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        }
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        if (newValue.length > 0 && ![newValue isEqualToString:currentValue]) {
            BOOL success = NO;
            
            // Handle different identifier types
            if ([key isEqualToString:@"IMEI"]) {
                success = [[IdentifierManager sharedManager] setCustomIMEI:newValue];
            } else if ([key isEqualToString:@"MEID"]) {
                success = [[IdentifierManager sharedManager] setCustomMEID:newValue];
            } else if ([key isEqualToString:@"DeviceModel"]) {
                success = [[IdentifierManager sharedManager] setCustomDeviceModel:newValue];
            } else if ([key isEqualToString:@"DeviceTheme"]) {
                // Validate theme value - must be "Light" or "Dark"
                if ([newValue isEqualToString:@"Light"] || [newValue isEqualToString:@"Dark"]) {
                    success = [[IdentifierManager sharedManager] setCustomDeviceTheme:newValue];
                } else {
                    // Show error alert for invalid theme value
                    UIAlertController *errorAlert = [UIAlertController 
                        alertControllerWithTitle:@"Invalid Theme" 
                        message:@"Theme must be either 'Light' or 'Dark'" 
                        preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [weakSelf presentViewController:errorAlert animated:YES completion:nil];
                    return;
                }
            }
            
            if (success) {
                // Find the appropriate card based on the identifier type
                UIView *targetCard = nil;
                if ([key isEqualToString:@"IMEI"]) {
                    targetCard = [weakSelf valueForKey:@"imeiCard"];
                } else if ([key isEqualToString:@"MEID"]) {
                    targetCard = [weakSelf valueForKey:@"meidCard"];
                } else if ([key isEqualToString:@"DeviceModel"]) {
                    targetCard = [weakSelf valueForKey:@"deviceModelCard"];
                } else if ([key isEqualToString:@"DeviceTheme"]) {
                    // For DeviceTheme, look for a card that has a title containing "Device Theme"
                    for (UIView *subview in weakSelf.view.subviews) {
                        if ([subview isKindOfClass:[UIScrollView class]]) {
                            for (UIView *stackView in subview.subviews) {
                                if ([stackView isKindOfClass:[UIStackView class]]) {
                                    for (UIView *card in [(UIStackView *)stackView arrangedSubviews]) {
                                        // Search for the header stack
                                        for (UIView *contentView in card.subviews) {
                                            if ([contentView isKindOfClass:[UIStackView class]]) {
                                                // This should be the content stack
                                                UIStackView *contentStack = (UIStackView *)contentView;
                                                if (contentStack.arrangedSubviews.count > 0) {
                                                    UIView *firstArrangedView = contentStack.arrangedSubviews[0];
                                                    if ([firstArrangedView isKindOfClass:[UIStackView class]]) {
                                                        // This should be the header stack
                                                        UIStackView *headerStack = (UIStackView *)firstArrangedView;
                                                        if (headerStack.arrangedSubviews.count > 0) {
                                                            UIView *headerView = headerStack.arrangedSubviews[0];
                                                            if ([headerView isKindOfClass:[UILabel class]]) {
                                                                UILabel *titleLabel = (UILabel *)headerView;
                                                                NSString *titleText = titleLabel.text ?: @"";
                                                                if ([titleText containsString:@"Device Theme"]) {
                                                                    targetCard = card;
                                                                    break;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        if (targetCard) break;
                                    }
                                    if (targetCard) break;
                                }
                            }
                            if (targetCard) break;
                        }
                    }
                } else {
                    // For other card types, find them in the stackView using a generic approach
                    for (UIView *subview in weakSelf.view.subviews) {
                        if ([subview isKindOfClass:[UIScrollView class]]) {
                            for (UIView *stackView in subview.subviews) {
                                if ([stackView isKindOfClass:[UIStackView class]]) {
                                    for (UIView *card in [(UIStackView *)stackView arrangedSubviews]) {
                                        // Search for a card with appropriate identifier value
                                        UILabel *valueLabel = [card viewWithTag:100];
                                        if (valueLabel && [card isKindOfClass:[UIView class]]) {
                                            targetCard = card;
                        break;
                                        }
                                    }
                                    if (targetCard) break;
                                }
                            }
                            if (targetCard) break;
                        }
                    }
                }
                
                // Update the value label in the card
                if (targetCard) {
                    UILabel *valueLabel = [targetCard viewWithTag:100];
                    if (valueLabel && [valueLabel isKindOfClass:[UILabel class]]) {
                        valueLabel.text = newValue;
                    }
                }
            }
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
