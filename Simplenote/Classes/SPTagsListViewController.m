#import "SPTagsListViewController.h"
#import "SPAppDelegate.h"
#import "SPOptionsViewController.h"
#import "SPObjectManager.h"
#import "SPBorderedView.h"
#import "SPTracker.h"
#import "SPTagListViewCell.h"
#import "Tag.h"

#import "VSThemeManager.h"
#import <Simperium/Simperium.h>
#import "Simplenote-Swift.h"


// MARK: - Constants
//
typedef NS_ENUM(NSInteger, SPTagsListSection) {
    SPTagsListSectionSystem = 0,
    SPTagsListSectionTags   = 1,
    SPTagsListSectionCount  = 2
};

typedef NS_ENUM(NSInteger, SPTagsListSystemRow) {
    SPTagsListSystemRowAllNotes = 0,
    SPTagsListSystemRowTrash    = 1,
    SPTagsListSystemRowSettings = 2,
    SPTagsListSystemRowCount    = 3
};

static const CGFloat kSPTagListEstimatedRowHeight = 44;
static const NSInteger kSPTagListRequestBatchSize = 20;


// MARK: - Private
//
@interface SPTagsListViewController () <NSFetchedResultsControllerDelegate,
                                        SPTagListViewCellDelegate,
                                        UIGestureRecognizerDelegate,
                                        UITextFieldDelegate,
                                        UITableViewDelegate,
                                        UITableViewDataSource>

@property (nonatomic, strong) IBOutlet UITableView          *tableView;
@property (nonatomic, strong) IBOutlet UIView               *tableHeaderView;
@property (nonatomic, strong) IBOutlet UIButton             *editTagsButton;
@property (nonatomic, strong) IBOutlet UILabel              *tagsLabel;
@property (nonatomic, strong) NSFetchedResultsController    *fetchedResultsController;
@property (nonatomic, strong) Tag                           *renameTag;
@property (nonatomic, strong) NSTimer                       *reloadTimer;
@property (nonatomic, assign) BOOL                          bEditing;
@property (nonatomic, assign) BOOL                          bVisible;

@end


// MARK: - SPTagsListViewController Implementation
//
@implementation SPTagsListViewController

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configureView];
    [self configureTableView];
    [self configureTableHeaderView];
    [self configureMenuController];
    [self startListeningToNotifications];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startListeningToKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopListeningToKeyboardNotifications];
}


#pragma mark - Interface Initialization

- (void)configureView {
    self.view.backgroundColor = [UIColor colorWithName:UIColorNameBackgroundColor];
}

- (void)configureTableView {
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = kSPTagListEstimatedRowHeight;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.tableView registerNib:SPTagListViewCell.loadNib forCellReuseIdentifier:SPTagListViewCell.reuseIdentifier];
}

- (void)configureTableHeaderView {
    self.tagsLabel.text = [NSLocalizedString(@"Tags", nil) uppercaseString];
    self.editTagsButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.editTagsButton setTitle:NSLocalizedString(@"Edit", nil) forState:UIControlStateNormal];
    [self.editTagsButton addTarget:self action:@selector(editTagsTap:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)configureMenuController {
    SEL renameSelector = sel_registerName("rename:");
    UIMenuItem *renameItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"Rename", @"Rename a tag")
                                                        action:renameSelector];
    [[UIMenuController sharedMenuController] setMenuItems:@[renameItem]];
    [[UIMenuController sharedMenuController] update];
}


#pragma mark - Notification Hooks

- (void)startListeningToNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(menuDidChangeVisibility:) name:UIMenuControllerDidHideMenuNotification object:nil];
    [nc addObserver:self selector:@selector(menuDidChangeVisibility:) name:UIMenuControllerDidShowMenuNotification object:nil];
    [nc addObserver:self selector:@selector(updateSortOrder:) name:SPAlphabeticalTagSortPreferenceChangedNotification object:nil];
    [nc addObserver:self selector:@selector(themeDidChange) name:VSThemeManagerThemeDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(stopListeningToKeyboardNotifications) name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)startListeningToKeyboardNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)stopListeningToKeyboardNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver: self name:UIKeyboardWillHideNotification object:nil];
    [nc removeObserver: self name:UIKeyboardWillShowNotification object:nil];
}


#pragma mark - Notification Handlers

- (VSTheme *)theme {
    return [[VSThemeManager sharedManager] theme];
}

- (void)themeDidChange {
    [self refreshStyle];
}

- (void)menuDidChangeVisibility:(UIMenuController *)menuController {
    self.tableView.allowsSelection = ![UIMenuController sharedMenuController].menuVisible;
}

- (void)updateSortOrder:(id)sender {
    self.fetchedResultsController.fetchRequest.sortDescriptors = [self sortDescriptors];

    NSError *error = nil;
    if (![self.fetchedResultsController performFetch:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    [self.tableView reloadData];
}


#pragma mark - Style

- (void)refreshStyle {
    UIColor *backgroundColor = [UIColor colorWithName:UIColorNameBackgroundColor];
    UIColor *tintColor = [UIColor colorWithName:UIColorNameTintColor];
    UIColor *tagsTextColor = [UIColor colorWithName:UIColorNameSimplenoteMidBlue];

    self.view.backgroundColor = backgroundColor;
    self.tagsLabel.textColor = tagsTextColor;
    [self.editTagsButton setTitleColor:tintColor forState:UIControlStateNormal];

    [self.tableView reloadData];

    [self.view setNeedsDisplay];
    [self.view setNeedsLayout];
}


#pragma mark - Button actions

- (void)editTagsTap:(UIButton *)sender {
    [self setEditing:!self.bEditing canceled:NO];
}


#pragma mark - Helper Methods

- (SPTagListViewCell *)cellForTag:(Tag *)tag {
    NSIndexPath *indexPath = [self tableViewIndexPathForTag:tag];
    return (SPTagListViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
}

- (NSIndexPath *)tableViewIndexPathForTag:(Tag *)tag {
    NSInteger row = [self.fetchedResultsController indexPathForObject:tag].row;
    return [NSIndexPath indexPathForItem:row inSection:SPTagsListSectionTags];
}

- (Tag *)tagAtTableViewIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.fetchedResultsController.fetchedObjects.count || indexPath.section != SPTagsListSectionTags) {
        return nil;
    }

    // Our FRC has just one section!
    NSIndexPath *resultsIndexPah = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
    return [self.fetchedResultsController objectAtIndexPath:resultsIndexPah];
}

- (NSInteger)numberOfTags {
    return self.fetchedResultsController.sections.firstObject.numberOfObjects;
}


#pragma mark - UITableViewDataSource

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == SPTagsListSectionTags && self.fetchedResultsController.fetchedObjects.count != 0) {
        return UITableViewAutomaticDimension;
    }

    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return section == SPTagsListSectionTags ? self.tableHeaderView : nil;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isTagRow = indexPath.section == SPTagsListSectionTags;
    BOOL isSortEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:SPAlphabeticalTagSortPref];

    return isTagRow && !isSortEnabled;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SPTagsListSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    switch (section) {
        case SPTagsListSectionSystem: {
            return SPTagsListSystemRowCount;
        }
        case SPTagsListSectionTags: {
            return self.numberOfTags;
        }
        default: {
            NSAssert(false, @"Unsupported section");
            return 0;
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPTagListViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SPTagListViewCell.reuseIdentifier forIndexPath:indexPath];

    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}

- (void)configureCell:(SPTagListViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case SPTagsListSectionSystem: {
            [self configureSystemCell:cell atIndexPath:indexPath];
            break;
        }
        case SPTagsListSectionTags: {
            [self configureTagCell:cell atIndexPath:indexPath];
            break;
        }
    }
}

- (void)configureSystemCell:(SPTagListViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {

    switch (indexPath.row) {
        case SPTagsListSystemRowAllNotes: {
            cell.tagNameTextField.text = NSLocalizedString(@"All Notes", nil);
            cell.leftImageView.image = [UIImage imageWithName:UIImageNameAllNotes];
            break;
        }
        case SPTagsListSystemRowTrash: {
            cell.tagNameTextField.text = NSLocalizedString(@"Trash-noun", nil);
            cell.leftImageView.image = [UIImage imageWithName:UIImageNameTrash];
            break;
        }
        case SPTagsListSystemRowSettings: {
            cell.tagNameTextField.text = NSLocalizedString(@"Settings", nil);
            cell.leftImageView.image = [UIImage imageWithName:UIImageNameSettings];
            break;
        }
    }
}

- (void)configureTagCell:(SPTagListViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {

    Tag *tag = [self tagAtTableViewIndexPath:indexPath];
    NSString *cellText = tag.name;

    cell.tagNameText = cellText;
    cell.accessibilityLabel = cellText;
    cell.delegate = self;
    cell.tagNameTextField.delegate = self;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    BOOL response = indexPath.section == SPTagsListSectionTags;
    if (response) {
        [SPTracker trackTagCellPressed];
    }
    
    return response;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    // Actions only allowed for Tags!
    return indexPath.section == SPTagsListSectionTags;
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    switch (indexPath.section) {
        case SPTagsListSectionSystem: {
            [self didSelectSystemRowAtIndexPath:indexPath];
            break;
        }
        case SPTagsListSectionTags: {
            [self didSelectTagAtIndexPath:indexPath];
            break;
        }
    }
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section == SPTagsListSectionTags && destinationIndexPath.section == SPTagsListSectionTags) {
        
        [[SPObjectManager sharedManager] moveTagFromIndex:sourceIndexPath.row
                                                  toIndex:destinationIndexPath.row];
        
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != SPTagsListSectionTags || proposedDestinationIndexPath.section != SPTagsListSectionTags) {

        return sourceIndexPath;
    }
    
    return proposedDestinationIndexPath ? proposedDestinationIndexPath : sourceIndexPath;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == SPTagsListSectionTags;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isTagRow = indexPath.section == SPTagsListSectionTags;
    return self.bEditing && isTagRow ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [SPTracker trackTagRowDeleted];
		[self removeTagAtIndexPath:indexPath];
    }
}


#pragma mark - Row Press Handlers

- (void)didSelectSystemRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.row) {
        case SPTagsListSystemRowAllNotes: {
            [self allNotesWasPressed];
            break;
        }

        case SPTagsListSystemRowTrash: {
            [self trashWasPressed];
            break;
        }

        case SPTagsListSystemRowSettings: {
            [self settingsWasPressed];
            break;
        }
    }
}

- (void)didSelectTagAtIndexPath:(NSIndexPath *)indexPath {
    Tag *tag = [self tagAtTableViewIndexPath:indexPath];

    if (self.bEditing) {
        [SPTracker trackTagRowRenamed];
        [self renameTagAction:tag];
    } else {
        [SPTracker trackListTagViewed];
        [self openNoteListForTagName:tag.name];
    }
}

- (void)allNotesWasPressed {
    [self openNoteListForTagName:nil];
}

- (void)trashWasPressed {
    [SPTracker trackTrashViewed];
    [self openNoteListForTagName:kSimplenoteTagTrashKey];
}

- (void)settingsWasPressed {
    [[SPAppDelegate sharedDelegate] showOptions];
}


#pragma mark - UITagListViewCellDelegate

- (void)tagListViewCellShouldRenameTag:(SPTagListViewCell *)cell {
    
    [SPTracker trackTagMenuRenamed];
    
    NSIndexPath *path = [self.tableView indexPathForCell:cell];
    [self renameTagAction:[self tagAtTableViewIndexPath:path]];
}

- (void)tagListViewCellShouldDeleteTag:(SPTagListViewCell *)cell {
    
    [SPTracker trackTagMenuDeleted];
    
    NSIndexPath *path = [self.tableView indexPathForCell:cell];
    [self removeTagAtIndexPath:path];
}

- (void)setEditing:(BOOL)editing canceled:(BOOL)isCanceled {
    
    if (self.bEditing == editing) {
        return;
    }
    
    self.bEditing = editing;

    self.tableView.allowsSelectionDuringEditing = YES;
    [self.tableView setEditing:editing animated:YES];
    
    if (editing) {
        [self.editTagsButton setTitle:NSLocalizedString(@"Done", nil) forState:UIControlStateNormal];
		[SPTracker trackTagEditorAccessed];
    } else {
        [self.editTagsButton setTitle:NSLocalizedString(@"Edit", nil) forState:UIControlStateNormal];
        [self.view endEditing:YES];
    }

    SPSidebarContainerViewController *noteListViewController = (SPSidebarContainerViewController *)[[SPAppDelegate sharedDelegate] noteListViewController];
    CGFloat newWidth = editing
        ? [self.theme floatForKey:@"containerViewSidePanelWidthExpanded"]
        : [self.theme floatForKey:@"containerViewSidePanelWidth"];
    CGRect frame = self.view.frame;
    frame.size.width = newWidth;

    CGRect notesFrame = noteListViewController.rootView.frame;
    notesFrame.origin.x = newWidth;
    if (!isCanceled) {
        // Make the tags list wider, and move the notes list over to accomodate for the new width
        [UIView animateWithDuration:UIKitConstants.animationShortDuration
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             self.view.frame = frame;
                             noteListViewController.rootView.frame = notesFrame;
                         } completion:^(BOOL finished) {
                             nil;
                         }];
    } else {
        self.view.frame = frame;
    }
    
    return;
}

- (void)openNoteListForTagName:(NSString *)tag {
    
    BOOL fetchNeeded = NO;

	SPAppDelegate *appDelegate = [SPAppDelegate sharedDelegate];
    // Only perform a fetch if the view has actually changed
    if (tag != nil || appDelegate.selectedTag) {
        fetchNeeded = ![tag isEqualToString:appDelegate.selectedTag] || (tag != nil && appDelegate.selectedTag == nil) || (appDelegate.selectedTag != nil && tag == nil);
	} else if (tag == nil && appDelegate.selectedTag != nil) {
        fetchNeeded = YES;
	}
    
	appDelegate.selectedTag = tag;
    
    if (fetchNeeded) {
        [[SPAppDelegate sharedDelegate].noteListViewController update];
    }
	
    [[self containerViewController] hideSidePanelAnimated:YES completion:nil];
}


#pragma mark - UIGestureDelegate methods

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    
    return YES;
}


#pragma mark - Tag Actions

- (void)removeTagAtIndexPath:(NSIndexPath *)indexPath {
    
    Tag *tag = [self tagAtTableViewIndexPath:indexPath];
    if (!tag) {
        return;
    }
    
    // see if this is the current tag
	SPAppDelegate *appDelegate = [SPAppDelegate sharedDelegate];
    if ([appDelegate.selectedTag isEqual:tag.name]) {
        appDelegate.selectedTag = nil;
        [appDelegate.noteListViewController update];
    }
    
    BOOL lastTag = [self numberOfTags] == 1;

    if ([[SPObjectManager sharedManager] removeTag:tag] && !lastTag) {
        
        [self.tableView beginUpdates];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationLeft];
        [self.tableView endUpdates];
    } else {
        [self.tableView reloadData];
    }
}

- (void)renameTagAction:(Tag *)tag {
    
    if (_renameTag) {
        SPTagListViewCell *cell = (SPTagListViewCell *)[self.tableView cellForRowAtIndexPath:[self tableViewIndexPathForTag:_renameTag]];
        [cell.tagNameTextField endEditing:YES];
    }
    
    _renameTag = tag;
    
    // begin editing the text field
    SPTagListViewCell *cell = [self cellForTag:tag];

    cell.isTextFieldEditable = YES;
    [cell.tagNameTextField becomeFirstResponder];
}


#pragma mark - UITextFieldDelegate methods

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    
    BOOL endEditing = NO;
    if ([string hasPrefix:@" "]) {
        string = nil;
        endEditing = YES;
    } else if ([string rangeOfString:@" "].location != NSNotFound) {
        string = [string substringWithRange:NSMakeRange(0, [string rangeOfString:@" "].location)];
        endEditing = YES;
    }
    
    if (string) {
        [textField setText:[textField.text stringByReplacingCharactersInRange:range
                                                              withString:string]];
    }
    
    if (endEditing) {
        [textField endEditing:YES];
    }
    
    return NO;
}


- (void)textFieldDidEndEditing:(UITextField *)textField {
    
    SPTagListViewCell *cell = (SPTagListViewCell *)[self.tableView cellForRowAtIndexPath:[self tableViewIndexPathForTag:_renameTag]];
    if (self.bEditing) {
        [cell setSelected:NO animated:YES];
    }

    // see if tag already exists, if not rename. If it does, revert back to original name
    BOOL renameTag = ![[SPObjectManager sharedManager] tagExists:textField.text];
    
    if (renameTag) {
        
        NSString *orignalTagName = _renameTag.name;
        NSString *newTagName = textField.text;
        [[SPObjectManager sharedManager] editTag:_renameTag title:newTagName];
        
        // see if this is the current tag
		SPAppDelegate *appDelegate = [SPAppDelegate sharedDelegate];
        if ([appDelegate.selectedTag isEqual:orignalTagName]) {
            appDelegate.selectedTag = newTagName;
            [appDelegate.noteListViewController update];
        }
    }
    else {
        textField.text = _renameTag.name;
    }
    
    _renameTag = nil;

    cell.tagNameText = textField.text;
    cell.isTextFieldEditable = NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    
    [textField resignFirstResponder];
    return YES;
}


#pragma mark - SidePanelDelegate

- (void)containerViewControllerDidHideSidePanel:(SPSidebarContainerViewController *)container {
    
    self.bVisible = NO;
    [self setEditing:NO canceled:YES];
    
}
- (void)containerViewControllerDidShowSidePanel:(SPSidebarContainerViewController *)container {
    
    self.bVisible = YES;
}

- (BOOL)containerViewControllerShouldShowSidePanel:(SPSidebarContainerViewController *)container {

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.bVisible) {
            [self.tableView reloadData];
        }
    });
    
    return YES;
}

- (void)containerViewController:(SPSidebarContainerViewController *)container didChangeContentInset:(UIEdgeInsets)contentInset {

    contentInset.bottom = self.tableView.contentInset.bottom;
    self.tableView.contentInset = contentInset;
    self.tableView.scrollIndicatorInsets = contentInset;
    self.tableView.contentOffset = CGPointMake(0, -contentInset.top);
}


#pragma mark - Fetched results controller

- (NSArray *)sortDescriptors {

    BOOL isAlphaSort = [[NSUserDefaults standardUserDefaults] boolForKey:SPAlphabeticalTagSortPref];
    NSSortDescriptor *sortDescriptor;
    if (isAlphaSort) {
        sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
                                                     ascending:YES
                                                      selector:@selector(localizedCaseInsensitiveCompare:)];
    } else {
        sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"index" ascending:YES];
    }

    return @[sortDescriptor];
}

- (void)performFetch {
    
    NSError *error = nil;
	if (![self.fetchedResultsController performFetch:&error])
    {
	    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
	}
    
    [self.tableView reloadData];
}

- (NSFetchedResultsController *)fetchedResultsController {
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }
    
    NSManagedObjectContext *context = [[SPAppDelegate sharedDelegate] managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Tag" inManagedObjectContext:context];

    NSFetchRequest *fetchRequest = [NSFetchRequest new];
    fetchRequest.entity = entity;
    fetchRequest.fetchBatchSize = kSPTagListRequestBatchSize;
    fetchRequest.sortDescriptors = [self sortDescriptors];

    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                                                managedObjectContext:context
                                                                                                  sectionNameKeyPath:nil
                                                                                                           cacheName:nil];
    aFetchedResultsController.delegate = self;
    self.fetchedResultsController = aFetchedResultsController;
    
    [self performFetch];
    
    return _fetchedResultsController;
}


#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    
    if (!self.bVisible) {
        return;
    }
    
    [self.reloadTimer invalidate];
    self.reloadTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                        target:self
                                                      selector:@selector(delayedReloadData)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)delayedReloadData {
    
    [self.tableView reloadData];
    
    [self.reloadTimer invalidate];
    self.reloadTimer = nil;
}


#pragma mark - KeyboardNotifications

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [(NSValue *)notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat duration = [(NSNumber *)notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue];

    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = MIN(keyboardFrame.size.height, keyboardFrame.size.width);

    [UIView animateWithDuration:duration animations:^{
        self.tableView.contentInset = insets;
     }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = 0;

    CGFloat duration = [(NSNumber *)notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue];
    
    [UIView animateWithDuration:duration animations:^{
        self.tableView.contentInset = insets;
     }];
}

@end
