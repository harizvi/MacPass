//
//  MPDocument.h
//  MacPass
//
//  Created by Michael Starke on 08.05.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MPDatabaseVersion.h"


APPKIT_EXTERN NSString *const MPDocumentDidAddGroupNotification;
APPKIT_EXTERN NSString *const MPDocumentDidAddEntryNotification;
APPKIT_EXTERN NSString *const MPDocumentDidRevertNotifiation;

APPKIT_EXTERN NSString *const MPDocumentEntryKey;
APPKIT_EXTERN NSString *const MPDocumentGroupKey;

APPKIT_EXTERN NSString *const MPDocumentRequestPasswordSaveNotification;

/*
 APPKIT_EXTERN NSString *const MPDocumentDidChangeCurrentItemNotification;
APPKIT_EXTERN NSString *const MPDocumentDidChangeCurrentGroupNotication;
APPKIT_EXTERN NSString *const MPDocumnetDidChangeCurrentEntryNotification;
*/

@class KdbGroup;
@class KdbEntry;
@class KdbTree;
@class Kdb4Tree;
@class Kdb3Tree;
@class Kdb4Entry;
@class UUID;
@class Binary;
@class BinaryRef;
@class StringField;
@class MPRootAdapter;

@interface MPDocument : NSDocument

/* true, if password and/or keyfile are set */
@property (assign, readonly) BOOL hasPasswordOrKey;
/* true, if lock screen is present (no phyiscal locking) */
@property (assign, nonatomic) BOOL locked;
@property (assign, readonly) BOOL decrypted;

@property (strong, readonly, nonatomic) KdbTree *tree;
@property (weak, readonly, nonatomic) KdbGroup *root;
@property (readonly, strong) MPRootAdapter *rootAdapter;
@property (weak, readonly) KdbGroup *trash;

@property (nonatomic, copy) NSString *password;
@property (nonatomic, strong) NSURL *key;

@property (assign, readonly) MPDatabaseVersion version;
@property (assign, readonly, getter = isReadOnly) BOOL readOnly;


/*
 State (active group/entry)
 */
@property (nonatomic, weak) KdbEntry *selectedEntry;
@property (nonatomic, weak) KdbGroup *selectedGroup;
@property (nonatomic, weak) id selectedItem;


- (id)initWithVersion:(MPDatabaseVersion)version;

#pragma mark Lock/Decrypt
- (void)lockDatabase:(id)sender;
- (BOOL)unlockWithPassword:(NSString *)password keyFileURL:(NSURL *)keyFileURL;

#pragma mark Data Lookup
/*
 Returns the entry for the given UUID, nil if none was found
 */
- (KdbEntry *)findEntry:(UUID *)uuid;
- (KdbGroup *)findGroup:(UUID *)uuid;

- (Kdb4Tree *)treeV4;
- (Kdb3Tree *)treeV3;

- (void)useGroupAsTrash:(KdbGroup *)group;
- (void)useGroupAsTemplate:(KdbGroup *)group;

- (BOOL)isItemTrashed:(id)item;

#pragma mark Export
- (void)writeXMLToURL:(NSURL *)url;

#pragma mark Undo Data Manipulation
/* Undoable Intiialization of elements */
- (KdbGroup *)createGroup:(KdbGroup *)parent;
- (KdbEntry *)createEntry:(KdbGroup *)parent;
- (StringField *)createStringField:(KdbEntry *)entry;

/*
 All non-setter undoable actions
*/

/* TODO in UNDO auslagen */
- (void)addStringField:(StringField *)field toEntry:(Kdb4Entry *)entry atIndex:(NSUInteger)index;
- (void)removeStringField:(StringField *)field formEntry:(Kdb4Entry *)entry;

- (void)deleteGroup:(KdbGroup *)group;
- (void)deleteEntry:(KdbEntry *)entry;

- (IBAction)emptyTrash:(id)sender;

@end

@interface MPDocument (Attachments)

- (void)addAttachment:(NSURL *)location toEntry:(KdbEntry *)anEntry;
/**
 item can be either a BinaryRef or an Kdb3Entry.
 */
- (void)saveAttachmentForItem:(id)item toLocation:(NSURL *)location;
- (void)removeAttachment:(BinaryRef *)reference fromEntry:(KdbEntry *)anEntry;
- (void)removeAttachmentFromEntry:(KdbEntry *)anEntry;
- (NSUInteger)nextBinaryId;
- (Binary *)findBinary:(BinaryRef *)reference;

@end