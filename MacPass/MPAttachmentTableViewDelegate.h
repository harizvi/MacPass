//
//  MPAttachmentTableViewDelegate.h
//  MacPass
//
//  Created by Michael Starke on 17.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPInspectorViewController;

@interface MPAttachmentTableViewDelegate : NSObject <NSTableViewDelegate>

@property (nonatomic, weak) MPInspectorViewController *viewController;

@end
