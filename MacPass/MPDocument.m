//
//  MPDocument.m
//  MacPass
//
//  Created by Michael Starke on 08.05.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPDocument.h"
#import "MPDocumentWindowController.h"

#import "MPDatabaseVersion.h"
#import "MPRootAdapter.h"
#import "MPIconHelper.h"
#import "MPActionHelper.h"
#import "MPSettingsHelper.h"
#import "MPNotifications.h"

#import "KdbLib.h"
#import "Kdb3Node.h"
#import "Kdb4Node.h"
#import "Kdb4Persist.h"
#import "KdbPassword.h"

#import "KdbGroup+KVOAdditions.h"
#import "Kdb4Entry+KVOAdditions.h"

#import "KdbEntry+Undo.h"
#import "KdbGroup+Undo.h"

#import "Kdb3Tree+NewTree.h"
#import "Kdb4Tree+NewTree.h"
#import "Kdb4Entry+MPAdditions.h"
#import "KdbGroup+MPTreeTools.h"
#import "KdbGroup+MPAdditions.h"

#import "DataOutputStream.h"

#import "DDXMLNode.h"

NSString *const MPDocumentDidAddGroupNotification         = @"com.hicknhack.macpass.MPDocumentDidAddGroupNotification";
NSString *const MPDocumentDidAddEntryNotification         = @"com.hicknhack.macpass.MPDocumentDidAddEntryNotification";
NSString *const MPDocumentDidRevertNotifiation            = @"com.hicknhack.macpass.MPDocumentDidRevertNotifiation";
NSString *const MPDocumentRequestPasswordSaveNotification = @"com.hicknhack.macpass.MPDocumentRequestPasswordSaveNotification";


NSString *const MPDocumentEntryKey                        = @"MPDocumentEntryKey";
NSString *const MPDocumentGroupKey                        = @"MPDocumentGroupKey";


@interface MPDocument () {
@private
  BOOL _didLockFile;
  NSData *_fileData;
}


@property (strong, nonatomic) KdbTree *tree;
@property (weak, nonatomic) KdbGroup *root;
@property (weak, nonatomic, readonly) KdbPassword *passwordHash;
@property (assign) MPDatabaseVersion version;

@property (assign, nonatomic) BOOL hasPasswordOrKey;
@property (assign) BOOL decrypted;
@property (assign) BOOL readOnly;

@property (strong) NSURL *lockFileURL;

@property (readonly) BOOL useTrash;
@property (strong) IBOutlet NSView *warningView;
@property (weak) IBOutlet NSImageView *warningViewImage;

@end


@implementation MPDocument

- (id)init
{
  return [self initWithVersion:MPDatabaseVersion4];
}
#pragma mark NSDocument essentials
- (id)initWithVersion:(MPDatabaseVersion)version {
  self = [super init];
  if(self) {
    _fileData = nil;
    _didLockFile = NO;
    _decrypted = YES;
    _hasPasswordOrKey = NO;
    _locked = NO;
    _readOnly = NO;
    _rootAdapter = [[MPRootAdapter alloc] init];
    _version = version;
    switch(_version) {
      case MPDatabaseVersion3:
        self.tree = [Kdb3Tree templateTree];
        break;
      case MPDatabaseVersion4:
        self.tree = [Kdb4Tree templateTree];
        //self.tree = [Kdb4Tree demoTree];
        break;
      default:
        self = nil;
        return nil;
    }
  }
  return self;
}

- (void)dealloc {
  [self _cleanupLock];
}

- (void)makeWindowControllers {
  MPDocumentWindowController *windowController = [[MPDocumentWindowController alloc] init];
  [self addWindowController:windowController];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
  [super windowControllerDidLoadNib:aController];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
  NSError *error = nil;
  [KdbWriterFactory persist:self.tree fileURL:url withPassword:self.passwordHash error:&error];
  if(error) {
    NSLog(@"%@", [error localizedDescription]);
    return NO;
  }
  return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
  /* FIXME: Logfile handling
   self.lockFileURL = [url URLByAppendingPathExtension:@"lock"];
   if([[NSFileManager defaultManager] fileExistsAtPath:[_lockFileURL path]]) {
   self.readOnly = YES;
   }
   else {
   [[NSFileManager defaultManager] createFileAtPath:[_lockFileURL path] contents:nil attributes:nil];
   _didLockFile = YES;
   self.readOnly = NO;
   }
   */
  /*
   Delete our old Tree, and just grab the data
   */
  self.tree = nil;
  _fileData = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:outError];
  self.decrypted = NO;
  return YES;
}

- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
  self.tree = nil;
  if([self readFromURL:absoluteURL ofType:typeName error:outError]) {
    [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidRevertNotifiation object:self];
    return YES;
  }
  return NO;
}

- (BOOL)isEntireFileLoaded {
  return _decrypted;
}

- (void)close {
  [self _cleanupLock];
  /*
   We store the last url. Restored windows are automatically handeld.
   If closeAllDocuments is set, all docs get this messgae
   */
  if([[self fileURL] isFileURL]) {
    [[NSUserDefaults standardUserDefaults] setObject:[self.fileURL absoluteString] forKey:kMPSettingsKeyLastDatabasePath];
  }
  [super close];
}

- (void)writeXMLToURL:(NSURL *)url {
  DataOutputStream *outputStream = [[DataOutputStream alloc] init];
  Kdb4Persist *persist = [[Kdb4Persist alloc] initWithTree:self.treeV4 outputStream:outputStream randomStream:nil];
  [persist persistWithOptions:DDXMLNodeCompactEmptyElement|DDXMLNodePrettyPrint];
  [outputStream.data writeToURL:url atomically:YES];
}

#pragma mark Lock/Unlock/Decrypt

- (BOOL)unlockWithPassword:(NSString *)password keyFileURL:(NSURL *)keyFileURL {
  self.key = keyFileURL;
  self.password = [password length] > 0 ? password : nil;
  @try {
    self.tree = [KdbReaderFactory load:[[self fileURL] path] withPassword:self.passwordHash];
  }
  @catch (NSException *exception) {
    return NO;
  }
  
  if([self.tree isKindOfClass:[Kdb4Tree class]]) {
    self.version = MPDatabaseVersion4;
  }
  else if( [self.tree isKindOfClass:[Kdb3Tree class]]) {
    self.version = MPDatabaseVersion3;
  }
  self.decrypted = YES;
  return YES;
}

- (void)lockDatabase:(id)sender {
  // Persist Tree into data
  self.tree = nil;
  self.locked = YES;
}


#pragma mark Custom Setter

- (void)setPassword:(NSString *)password {
  if(![_password isEqualToString:password]) {
    _password = [password copy];
    [self _updateIsSecured];
  }
}

- (void)setKey:(NSURL *)key {
  if(![[_key absoluteString] isEqualToString:[key absoluteString]]) {
    _key = key;
    [self _updateIsSecured];
  }
}

- (KdbPassword *)passwordHash {
  
  return [[KdbPassword alloc] initWithPassword:self.password passwordEncoding:NSUTF8StringEncoding keyFileURL:self.key];
}

+ (BOOL)autosavesInPlace
{
  return NO;
}

- (void)saveDocument:(id)sender {
  if(self.hasPasswordOrKey) {
    [super saveDocument:sender];
  }
  else {
    [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentRequestPasswordSaveNotification object:self userInfo:nil];
  }
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel {
  if(self.hasPasswordOrKey) {
    [savePanel setAccessoryView:nil];
    return YES;
  }
  return NO;
}

- (void)setSelectedGroup:(KdbGroup *)selectedGroup {
  if(_selectedGroup != selectedGroup) {
    _selectedGroup = selectedGroup;
  }
  self.selectedItem = _selectedGroup;
}

- (void)setSelectedEntry:(KdbEntry *)selectedEntry {
  if(_selectedEntry != selectedEntry) {
    _selectedEntry = selectedEntry;
  }
  self.selectedItem = selectedEntry;
}

- (void)setSelectedItem:(id)selectedItem {
  if(_selectedItem != selectedItem) {
    _selectedItem = selectedItem;
    [[NSNotificationCenter defaultCenter] postNotificationName:MPCurrentItemChangedNotification object:self];
  }
}

#pragma mark Data Accesors
- (void)setTree:(KdbTree *)tree {
  if(_tree != tree) {
    _tree = tree;
    self.rootAdapter.tree = _tree;
  }
}

- (KdbGroup *)root {
  return self.tree.root;
}

- (KdbEntry *)findEntry:(UUID *)uuid {
  return [self.root entryForUUID:uuid];
}

- (KdbGroup *)findGroup:(UUID *)uuid {
  return [self.root groupForUUID:uuid];
}

- (Kdb3Tree *)treeV3 {
  switch (_version) {
    case MPDatabaseVersion3:
      NSAssert(self.tree == nil || [self.tree isKindOfClass:[Kdb3Tree class]], @"Tree has to be Version3");
      return (Kdb3Tree *)self.tree;
    case MPDatabaseVersion4:
      return nil;
    default:
      return nil;
  }
}

- (Kdb4Tree *)treeV4 {
  switch (_version) {
    case MPDatabaseVersion3:
      return nil;
    case MPDatabaseVersion4:
      NSAssert(self.tree == nil || [self.tree isKindOfClass:[Kdb4Tree class]], @"Tree has to be Version4");
      return (Kdb4Tree *)self.tree;
    default:
      return nil;
  }
}

- (BOOL)useTrash {
  if(self.treeV4) {
    return self.treeV4.recycleBinEnabled;
  }
  return NO;
}

- (KdbGroup *)trash {
  static KdbGroup *_trash = nil;
  if(self.useTrash) {
    BOOL trashValid = [((Kdb4Group *)_trash).uuid isEqual:self.treeV4.recycleBinUuid];
    if(!trashValid) {
      _trash = [self findGroup:self.treeV4.recycleBinUuid];
    }
    return _trash;
  }
  return nil;
}

- (BOOL)isItemTrashed:(id)item {
  BOOL validItem = [item isKindOfClass:[KdbEntry class]] || [item isKindOfClass:[KdbGroup class]];
  if(!item) {
    return NO;
  }
  if(item == self.trash) {
    return NO; // No need to look further as this is the trashcan
  }
  if(validItem) {
    BOOL isTrashed = NO;
    id parent = [item parent];
    while( parent && !isTrashed ) {
      isTrashed = (parent == self.trash);
      parent = [parent parent];
    }
    return isTrashed;
  }
  return NO;
}

- (void)useGroupAsTrash:(KdbGroup *)group {
  if(self.useTrash) {
    Kdb4Group *groupv4 = (Kdb4Group *)group;
    if(![self.treeV4.recycleBinUuid isEqual:groupv4.uuid]) {
      self.treeV4.recycleBinUuid = groupv4.uuid;
    }
  }
}

- (void)useGroupAsTemplate:(KdbGroup *)group {
  Kdb4Group *groupv4 = (Kdb4Group *)group;
  if([self.treeV4.entryTemplatesGroup isEqual:groupv4.uuid]) {
    self.treeV4.entryTemplatesGroup = groupv4.uuid;
  }
}

#pragma mark Data manipulation
- (KdbEntry *)createEntry:(KdbGroup *)parent {
  if(!parent) {
    return nil; // No parent
  }
  if(parent == self.trash) {
    return nil; // no new Groups in trash
  }
  if([self isItemTrashed:parent]) {
    return nil;
  }
  KdbEntry *newEntry = [self.tree createEntry:parent];
  newEntry.title = NSLocalizedString(@"DEFAULT_ENTRY_TITLE", @"Title for a newly created entry");
  if(self.treeV4 && ([self.treeV4.defaultUserName length] > 0)) {
    newEntry.title = self.treeV4.defaultUserName;
  }
  [parent addEntryUndoable:newEntry atIndex:[parent.entries count]];
  NSDictionary *userInfo = @{ MPDocumentEntryKey : newEntry };
  [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidAddEntryNotification object:self userInfo:userInfo];
  return newEntry;
}

- (KdbGroup *)createGroup:(KdbGroup *)parent {
  if(!parent) {
    return nil; // no parent!
  }
  if(parent == self.trash) {
    return nil; // no new Groups in trash
  }
  if([self isItemTrashed:parent]) {
    return nil;
  }
  KdbGroup *newGroup = [self.tree createGroup:parent];
  newGroup.name = NSLocalizedString(@"DEFAULT_GROUP_NAME", @"Title for a newly created group");
  newGroup.image = MPIconFolder;
  [parent addGroupUndoable:newGroup atIndex:[parent.groups count]];
  NSDictionary *userInfo = @{ MPDocumentGroupKey : newGroup };
  [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidAddGroupNotification object:self userInfo:userInfo];
  return newGroup;
}

- (StringField *)createStringField:(KdbEntry *)entry {
  // TODO: Localize!
  if(![entry isKindOfClass:[Kdb4Entry class]]) {
    return nil;
  }
  Kdb4Entry *entryV4 = (Kdb4Entry *)entry;
  NSString *title = NSLocalizedString(@"DEFAULT_CUSTOM_FIELD_TITLE", @"Default Titel for new Custom-Fields");
  NSString *value = NSLocalizedString(@"DEFAULT_CUSTOM_FIELD_VALUE", @"Default Value for new Custom-Fields");
  title = [entryV4 uniqueKeyForProposal:title];
  StringField *newStringField = [StringField stringFieldWithKey:title andValue:value];
  [self addStringField:newStringField toEntry:entryV4 atIndex:[entryV4.stringFields count]];
  return newStringField;
}

- (void)deleteEntry:(KdbEntry *)entry {
  if(self.useTrash) {
    if(!self.trash) {
      [self _createTrashGroup];
    }
    if([self isItemTrashed:entry]) {
      return; // Entry is already trashed
    }
    [entry moveToTrashUndoable:self.trash atIndex:[self.trash.entries count]];
  }
  else {
    [entry deleteUndoable];
  }
  self.selectedEntry = nil;
}

- (void)deleteGroup:(KdbGroup *)group {
  if(self.useTrash) {
    if(!self.trash) {
      [self _createTrashGroup];
    }
    if( (group == self.trash) || [self isItemTrashed:group] ) {
      return; //Groups already trashed cannot be deleted
    }
    [group moveToTrashUndoable:self.trash atIndex:[self.trash.groups count]];
  }
  else {
    [group deleteUndoable];
  }
}

#pragma mark CustomFields

- (void)addStringField:(StringField *)field toEntry:(Kdb4Entry *)entry atIndex:(NSUInteger)index {
  [[[self undoManager] prepareWithInvocationTarget:self] removeStringField:field formEntry:entry];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_ADD_STRING_FIELD", @"Add Stringfield Undo")];
  field.entry = entry;
  [entry insertObject:field inStringFieldsAtIndex:index];
}

- (void)removeStringField:(StringField *)field formEntry:(Kdb4Entry *)entry {
  NSInteger index = [entry.stringFields indexOfObject:field];
  if(NSNotFound == index) {
    return; // Nothing found to be removed
  }
  [[[self undoManager] prepareWithInvocationTarget:self] addStringField:field toEntry:entry atIndex:index];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_DELETE_STRING_FIELD", @"Delte Stringfield undo")];
  field.entry = nil;
  [entry removeObjectFromStringFieldsAtIndex:index];
}

#pragma mark Actions

- (void)emptyTrash:(id)sender {
  if(self.version != MPDatabaseVersion4) {
    return; // We have no trash on those file types
  }
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert setMessageText:NSLocalizedString(@"WARNING_ON_EMPTY_TRASH_TITLE", "")];
  [alert setInformativeText:NSLocalizedString(@"WARNING_ON_EMPTY_TRASH_DESCRIPTION", "Informative Text displayed when clearing the Trash")];
  [alert addButtonWithTitle:NSLocalizedString(@"EMPTY_TRASH", "Empty Trash")];
  [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", "Cancel")];
  
  [[alert buttons][1] setKeyEquivalent:[NSString stringWithFormat:@"%c", 0x1b]];
  
  NSWindow *window = [[self windowControllers][0] window];
  [alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void) alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
  if(returnCode == NSAlertFirstButtonReturn) {
    [self _emptyTrash];
  }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem {
  if([anItem action] == [MPActionHelper actionOfType:MPActionEmptyTrash]) {
    BOOL hasGroups = [self.trash.groups count] > 0;
    BOOL hasEntries = [self.trash.entries count] > 0;
    return (hasEntries || hasGroups);
  }
  
  return [super validateUserInterfaceItem:anItem];
}

#pragma mark Private
- (void)_updateIsSecured {
  BOOL securePassword = ([self.password length] > 0);
  BOOL secureKey = (nil != self.key);
  self.hasPasswordOrKey = (secureKey || securePassword);
}

- (void)_cleanupLock {
  if(_didLockFile) {
    [[NSFileManager defaultManager] removeItemAtURL:_lockFileURL error:nil];
    _didLockFile = NO;
  }
}

- (KdbGroup *)_createTrashGroup {
  /* Maybe push the stuff to the Tree? */
  if(self.version == MPDatabaseVersion3) {
    return nil;
  }
  else if(self.version == MPDatabaseVersion4) {
    KdbGroup *trash = [self.tree createGroup:self.tree.root];
    trash.name = NSLocalizedString(@"TRASH", @"Name for the trash group");
    trash.image = MPIconTrash;
    [self.tree.root insertObject:trash inGroupsAtIndex:[self.tree.root.groups count]];
    self.treeV4.recycleBinUuid = ((Kdb4Group *)trash).uuid;
    return trash;
  }
  else {
    NSAssert(NO, @"Database with unknown version: %ld", _version);
    return nil;
  }
}

- (void)_emptyTrash {
  for(KdbEntry *entry in [self.trash childEntries]) {
    [[self undoManager] removeAllActionsWithTarget:entry];
  }
  for(KdbGroup *group in [self.trash childGroups]) {
    [[self undoManager] removeAllActionsWithTarget:group];
  }
  [self _cleanTrashedBinaries];
  [self.trash clear];
}

- (void)_cleanTrashedBinaries {
  NSMutableSet *clearKeys = [[NSMutableSet alloc] initWithCapacity:20];
  NSMutableArray *clearBinaries = [[NSMutableArray alloc] initWithCapacity:[self.treeV4.binaries count]];
  for(Kdb4Entry *entry in [self.trash childEntries]) {
    for(BinaryRef *binaryRef in entry.binaries) {
      [clearKeys addObject:@(binaryRef.ref)];
    }
  }
  for(Binary *binary in self.treeV4.binaries) {
    if([clearKeys containsObject:@(binary.binaryId)]) {
      [clearBinaries addObject:binary];
    }
  }
  [self.treeV4.binaries removeObjectsInArray:clearBinaries];
}

@end
