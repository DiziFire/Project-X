#import "DomainManagementViewController.h"
#import "DomainBlockingSettings.h"
#import <Preferences/PSSpecifier.h>

@implementation DomainManagementViewController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];
        DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
        
        // Header section
        PSSpecifier *headerGroup = [PSSpecifier emptyGroupSpecifier];
        [headerGroup setProperty:@"Domain Blocking Configuration" forKey:@"headerText"];
        [headerGroup setProperty:@"Protection against device detection used by ride-sharing and food delivery apps. Use suggested domains below or add your own custom domains." forKey:@"footerText"];
        [specifiers addObject:headerGroup];
        
        // Suggested domains section with interactive buttons
        PSSpecifier *suggestedGroup = [PSSpecifier emptyGroupSpecifier];
        [suggestedGroup setProperty:@"Suggested Domains" forKey:@"headerText"];
        [suggestedGroup setProperty:@"Tap any domain to copy it or add it directly. These are commonly used by ride-sharing and food delivery apps." forKey:@"footerText"];
        [specifiers addObject:suggestedGroup];
        
        // Apple Device Detection (Critical)
        NSArray *appleDomains = @[
            @{@"domain": @"devicecheck.apple.com", @"description": @"🍎 Apple DeviceCheck (Critical)", @"category": @"Apple"},
            @{@"domain": @"appattest.apple.com", @"description": @"🍎 Apple App Attestation", @"category": @"Apple"}
        ];
        
        // Sift Fraud Detection  
        NSArray *siftDomains = @[
            @{@"domain": @"api.sift.com", @"description": @"🔍 Sift API (DoorDash, Lyft)", @"category": @"Sift"},
            @{@"domain": @"cdn.sift.com", @"description": @"🔍 Sift CDN", @"category": @"Sift"},
            @{@"domain": @"sift.com", @"description": @"🔍 Sift Main Domain", @"category": @"Sift"}
        ];
        
        // ThreatMetrix
        NSArray *threatMetrixDomains = @[
            @{@"domain": @"h.online-metrix.net", @"description": @"🛡️ ThreatMetrix Collector (Uber)", @"category": @"ThreatMetrix"},
            @{@"domain": @"fp.threatmetrix.com", @"description": @"🛡️ ThreatMetrix Fingerprint", @"category": @"ThreatMetrix"},
            @{@"domain": @"api.threatmetrix.com", @"description": @"🛡️ ThreatMetrix API", @"category": @"ThreatMetrix"}
        ];
        
        // Firebase
        NSArray *firebaseDomains = @[
            @{@"domain": @"app-measurement.com", @"description": @"📊 Firebase Analytics", @"category": @"Firebase"},
            @{@"domain": @"firebaseappcheck.googleapis.com", @"description": @"📊 Firebase App Check", @"category": @"Firebase"},
            @{@"domain": @"firebase.googleapis.com", @"description": @"📊 Firebase Services", @"category": @"Firebase"}
        ];
        
        // Iovation
        NSArray *iovationDomains = @[
            @{@"domain": @"mpsnare.iesnare.com", @"description": @"🎯 Iovation Device Fingerprint", @"category": @"Iovation"},
            @{@"domain": @"ci-mpsnare.iovationapi.com", @"description": @"🎯 Iovation API", @"category": @"Iovation"}
        ];
            
        // FingerprintJS
        NSArray *fingerprintDomains = @[
            @{@"domain": @"cdn.fingerprint.com", @"description": @"👤 FingerprintJS CDN", @"category": @"FingerprintJS"},
            @{@"domain": @"fingerprint.com", @"description": @"👤 FingerprintJS Main", @"category": @"FingerprintJS"}
        ];
        
        // Combine all suggested domains
        NSArray *allSuggestedDomains = [NSArray arrayWithObjects:appleDomains, siftDomains, threatMetrixDomains, firebaseDomains, iovationDomains, fingerprintDomains, nil];
        
        for (NSArray *categoryDomains in allSuggestedDomains) {
            for (NSDictionary *domainInfo in categoryDomains) {
                    NSString *domain = domainInfo[@"domain"];
                    NSString *description = domainInfo[@"description"];
                    
                // Check if domain is already added as custom domain
                BOOL isAlreadyAdded = [settings isCustomDomain:domain];
                NSString *buttonTitle = isAlreadyAdded ? [NSString stringWithFormat:@"✅ %@", description] : description;
                    
                PSSpecifier *domainButton = [PSSpecifier preferenceSpecifierNamed:buttonTitle
                                                                          target:self
                                                                             set:NULL
                                                                             get:NULL
                                                                          detail:Nil
                                                                            cell:PSButtonCell
                                                                            edit:Nil];
                [domainButton setProperty:domain forKey:@"suggestedDomain"];
                [domainButton setProperty:description forKey:@"domainDescription"];
                [domainButton setProperty:@"suggested" forKey:@"domainType"];
                [domainButton setButtonAction:@selector(suggestedDomainTapped:)];
                domainButton.identifier = [NSString stringWithFormat:@"suggested_%@", domain];
                    
                // Color coding: green if already added, blue if available
                if (isAlreadyAdded) {
                    [domainButton setProperty:[UIColor systemGreenColor] forKey:@"textColor"];
                } else {
                    [domainButton setProperty:[UIColor systemBlueColor] forKey:@"textColor"];
                    }
                    
                [specifiers addObject:domainButton];
            }
        }
        
        // Custom domain section
        PSSpecifier *customGroup = [PSSpecifier emptyGroupSpecifier];
        [customGroup setProperty:@"Your Domains" forKey:@"headerText"];
        [customGroup setProperty:@"Your added domains appear here. Tap ⚙️ to edit/delete domains. Toggle switches show 'Enable domain.com' when OFF or 'Enabled domain.com' when ON." forKey:@"footerText"];
        [specifiers addObject:customGroup];
        
        // Add custom domain button
        PSSpecifier *addSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Add Custom Domain"
                                                              target:self
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:Nil
                                                                cell:PSButtonCell
                                                                edit:Nil];
        [addSpecifier setProperty:@YES forKey:@"enabled"];
        [addSpecifier setButtonAction:@selector(addCustomDomainTapped)];
        [specifiers addObject:addSpecifier];
        
        // FIXED: Separate gear icon button and toggle switch for each custom domain
        NSArray *customDomains = [settings getCustomDomains];
        for (NSDictionary *domainInfo in customDomains) {
            NSString *domain = domainInfo[@"domain"];
            
            // 1. Gear icon button for settings (edit/delete)
            PSSpecifier *gearButton = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"⚙️ %@", domain]
                                                                  target:self
                                                                     set:NULL
                                                                     get:NULL
                                                                  detail:Nil
                                                                      cell:PSButtonCell
                                                                      edit:Nil];
            [gearButton setProperty:domain forKey:@"customDomain"];
            [gearButton setProperty:@"gearButton" forKey:@"domainType"];
            [gearButton setButtonAction:@selector(customDomainSettingsTapped:)];
            gearButton.identifier = [NSString stringWithFormat:@"gear_%@", domain];
            [gearButton setProperty:[UIColor systemBlueColor] forKey:@"textColor"];
            [specifiers addObject:gearButton];
            
            // 2. Toggle switch for enable/disable with dynamic status text
            BOOL isEnabled = [settings isCustomDomainEnabled:domain];
            NSString *actionText = isEnabled ? @"Enabled" : @"Enable";
            PSSpecifier *toggleSwitch = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"    %@ %@", actionText, domain]
                                                                      target:self
                                                                         set:@selector(setCustomDomainEnabled:forSpecifier:)
                                                                         get:@selector(getCustomDomainEnabled:)
                                                                      detail:Nil
                                                                        cell:PSSwitchCell
                                                                    edit:Nil];
            [toggleSwitch setProperty:domain forKey:@"id"];
            [toggleSwitch setProperty:domain forKey:@"key"];
            [toggleSwitch setProperty:@YES forKey:@"enabled"];
            [toggleSwitch setProperty:@"custom" forKey:@"domainType"]; // Mark as custom for deletion tracking
            toggleSwitch.identifier = domain;
            [toggleSwitch setProperty:[UIColor systemGrayColor] forKey:@"textColor"];
            [specifiers addObject:toggleSwitch];
        }
        
        _specifiers = [specifiers copy];
    }
    return _specifiers;
}

// No optional domains - removed getter/setter methods

// FIXED: Getter for custom domain switch state
- (id)getCustomDomainEnabled:(PSSpecifier *)specifier {
    NSString *domain = [specifier propertyForKey:@"id"];
    DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
    return @([settings isCustomDomainEnabled:domain]);
}

// ENHANCED: Setter for custom domain switch state with dynamic label update
- (void)setCustomDomainEnabled:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *domain = [specifier propertyForKey:@"id"];
    BOOL enabled = [value boolValue];
    DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
    [settings setCustomDomainEnabled:domain enabled:enabled];
    
    // Update the specifier name to show current status
    NSString *actionText = enabled ? @"Enabled" : @"Enable";
    NSString *newName = [NSString stringWithFormat:@"    %@ %@", actionText, domain];
    [specifier setName:newName];
    
    // Find and update the cell to reflect the new name immediately
    NSInteger specifierIndex = [self indexOfSpecifier:specifier];
    if (specifierIndex != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:specifierIndex inSection:0];
        UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
        if (cell) {
            cell.textLabel.text = newName;
        }
    }
}

- (void)addCustomDomainTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom Domain"
                                                                 message:@"Enter domain name only (e.g., doordash.com)\n\nThis will block the main domain and all subdomains:\n• doordash.com ✓\n• api.doordash.com ✓\n• track.doordash.com ✓"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"doordash.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                           style:UIAlertActionStyleCancel 
                                         handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" 
                                           style:UIAlertActionStyleDefault 
                                         handler:^(UIAlertAction *action) {
        NSString *domain = alert.textFields.firstObject.text;
        if (domain.length > 0) {
            // Enhanced domain input cleanup
            domain = [domain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            domain = [domain stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            domain = [domain stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            domain = [domain stringByReplacingOccurrencesOfString:@"www." withString:@""];
            domain = [domain stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
            domain = [domain lowercaseString];
            
            // Enhanced validation
            if (domain.length > 0 && [domain containsString:@"."] && ![domain hasPrefix:@"."] && ![domain hasSuffix:@"."]) {
                DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
                
                // Check if it's already a custom domain
                if ([settings isCustomDomain:domain]) {
                    [self showAlertWithTitle:@"Domain Already Exists" message:@"This domain already exists. You can toggle it on/off in the list below."];
                    return;
                }
                
                // Add as custom domain
                [settings addDomain:domain];
                
                // Show success feedback
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Domain Added" 
                                                                                       message:[NSString stringWithFormat:@"Successfully added '%@'.", domain]
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
                
                [self reloadSpecifiers];
            } else {
                [self showAlertWithTitle:@"Invalid Domain Format" 
                                 message:@"Please enter a valid domain name without protocol or path.\n\nExamples:\n✓ doordash.com\n✓ api.sift.com\n✓ devicecheck.apple.com\n\n❌ https://doordash.com\n❌ www.doordash.com/path"];
            }
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ENHANCED: Edit custom domain functionality
- (void)editCustomDomain:(NSString *)currentDomain atIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Custom Domain"
                                                                 message:@"Modify the domain name (e.g., doordash.com)\n\nThis will block the main domain and all subdomains:\n• doordash.com ✓\n• api.doordash.com ✓\n• track.doordash.com ✓"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentDomain; // Pre-fill with current domain
        textField.placeholder = @"doordash.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        // Select all text for easy editing
        dispatch_async(dispatch_get_main_queue(), ^{
            [textField selectAll:nil];
        });
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                           style:UIAlertActionStyleCancel 
                                         handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" 
                                           style:UIAlertActionStyleDefault 
                                         handler:^(UIAlertAction *action) {
        NSString *newDomain = alert.textFields.firstObject.text;
        if (newDomain.length > 0) {
            // Enhanced domain input cleanup
            newDomain = [newDomain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            newDomain = [newDomain stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            newDomain = [newDomain stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            newDomain = [newDomain stringByReplacingOccurrencesOfString:@"www." withString:@""];
            newDomain = [newDomain stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
            newDomain = [newDomain lowercaseString];
            
            // Enhanced validation
            if (newDomain.length > 0 && [newDomain containsString:@"."] && ![newDomain hasPrefix:@"."] && ![newDomain hasSuffix:@"."]) {
            DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
            
                // Check if the new domain is the same as current (no change)
                if ([newDomain isEqualToString:currentDomain]) {
                    return; // No change, just dismiss
                }
                
                // Check if it's already another domain
                if ([settings isCustomDomain:newDomain]) {
                    [self showAlertWithTitle:@"Domain Already Exists" message:@"This domain already exists. Please choose a different domain."];
                    return;
                }
                
                // Get the current enabled state before removing
                BOOL wasEnabled = [settings isCustomDomainEnabled:currentDomain];
                
                // Remove the old domain
                [settings removeCustomDomain:currentDomain];
                
                // Add the new domain with the same enabled state
                [settings addDomain:newDomain]; // This adds to custom domains
                [settings setCustomDomainEnabled:newDomain enabled:wasEnabled];
                
                // Show success feedback
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Domain Updated" 
                                                                                       message:[NSString stringWithFormat:@"Successfully updated domain from '%@' to '%@'.", currentDomain, newDomain]
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
                
                // Reload the entire specifiers to update the UI
                [self reloadSpecifiers];
            } else {
                [self showAlertWithTitle:@"Invalid Domain Format" 
                                 message:@"Please enter a valid domain name without protocol or path.\n\nExamples:\n✓ doordash.com\n✓ api.sift.com\n✓ devicecheck.apple.com\n\n❌ https://doordash.com\n❌ www.doordash.com/path"];
            }
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// FIXED: Handle gear button taps (much cleaner than gesture recognizers)
- (void)customDomainSettingsTapped:(PSSpecifier *)specifier {
    NSString *domain = [specifier propertyForKey:@"customDomain"];
    if (domain) {
        [self showCustomDomainActionSheet:domain];
    }
}

// ENHANCED: Handle suggested domain button taps
- (void)suggestedDomainTapped:(PSSpecifier *)specifier {
    NSString *domain = [specifier propertyForKey:@"suggestedDomain"];
    NSString *description = [specifier propertyForKey:@"domainDescription"];
    
    if (!domain) return;
    
    DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
    BOOL isAlreadyAdded = [settings isCustomDomain:domain];
    
    NSString *title = [NSString stringWithFormat:@"Domain: %@", domain];
    NSString *message = [NSString stringWithFormat:@"%@\n\nChoose an action:", description];
    
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Copy to clipboard action (always available)
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📋 Copy Domain"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = domain;
        
        // Show confirmation
        UIAlertController *copied = [UIAlertController alertControllerWithTitle:@"Copied!"
                                                                        message:[NSString stringWithFormat:@"'%@' copied to clipboard", domain]
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [copied addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:copied animated:YES completion:nil];
    }]];
    
    if (isAlreadyAdded) {
        // Domain is already added - show enable/disable and remove options
        BOOL isEnabled = [settings isCustomDomainEnabled:domain];
        NSString *toggleTitle = isEnabled ? @"🔴 Disable Domain" : @"🟢 Enable Domain";
        
        [actionSheet addAction:[UIAlertAction actionWithTitle:toggleTitle
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
            [settings setCustomDomainEnabled:domain enabled:!isEnabled];
            [self reloadSpecifiers];
            
            NSString *statusMessage = !isEnabled ? @"Domain enabled successfully" : @"Domain disabled successfully";
            [self showAlertWithTitle:@"Domain Updated" message:statusMessage];
        }]];
        
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"🗑️ Remove Domain"
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(UIAlertAction *action) {
            [settings removeCustomDomain:domain];
            [self reloadSpecifiers];
            [self showAlertWithTitle:@"Domain Removed" message:[NSString stringWithFormat:@"'%@' has been removed from your domains.", domain]];
        }]];
    } else {
        // Domain is not added - show add option
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"➕ Add Domain"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
            [settings addDomain:domain];
            [self reloadSpecifiers];
            [self showAlertWithTitle:@"Domain Added" message:[NSString stringWithFormat:@"'%@' has been added to your domains and is now enabled.", domain]];
        }]];
    }
    
    // Cancel action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    
    // For iPad support
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = self.view;
        actionSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

// ENHANCED: Add additional gestures for better accessibility
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add long press gesture as alternative for settings
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.table addGestureRecognizer:longPress];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint tapLocation = [gesture locationInView:self.table];
        NSIndexPath *indexPath = [self.table indexPathForRowAtPoint:tapLocation];
        
        if (indexPath) {
            PSSpecifier *specifier = [self specifierAtIndex:indexPath.row];
            NSString *domainType = [specifier propertyForKey:@"domainType"];
            
            // Handle long press on either gear button or toggle switch for custom domains
            if ([domainType isEqualToString:@"gearButton"]) {
                NSString *domain = [specifier propertyForKey:@"customDomain"];
                [self showCustomDomainActionSheet:domain];
            } else if ([domainType isEqualToString:@"custom"]) {
                NSString *domain = specifier.identifier;
                [self showCustomDomainActionSheet:domain];
            }
        }
    }
}

// ENHANCED: Show action sheet for custom domain options
- (void)showCustomDomainActionSheet:(NSString *)domain {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Custom Domain: %@", domain]
                                                                         message:@"Choose an action"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Edit action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"✏️ Edit Domain"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *action) {
        [self editCustomDomain:domain atIndexPath:nil];
    }]];
    
    // Delete action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🗑️ Delete Domain"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction *action) {
        [self deleteCustomDomain:domain];
    }]];
    
    // Cancel action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    
    // For iPad support
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = self.view;
        actionSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

// ENHANCED: Separate delete method for better organization
- (void)deleteCustomDomain:(NSString *)domain {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Custom Domain"
                                                                 message:[NSString stringWithFormat:@"Are you sure you want to delete '%@'?", domain]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                           style:UIAlertActionStyleCancel 
                                         handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" 
                                           style:UIAlertActionStyleDestructive 
                                         handler:^(UIAlertAction *action) {
        DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
        [settings removeCustomDomain:domain];
        
        // Show success feedback
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Domain Deleted" 
                                                                               message:[NSString stringWithFormat:@"Successfully removed '%@' from custom domains.", domain]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:successAlert animated:YES completion:nil];
        
        [self reloadSpecifiers];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}



@end
