/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "CKComponent.h"
#import "CKComponentProvider.h"
#import "CKComponentScope.h"
#import "CKComponentSubclass.h"
#import "CKCompositeComponent.h"
#import "CKComponentController.h"
#import "CKCollectionViewTransactionalDataSource.h"
#import "CKTransactionalComponentDataSourceConfiguration.h"
#import "CKTransactionalComponentDataSourceChangeset.h"

@interface CKTransactionalComponentDataSourceIntegrationTestComponent : CKCompositeComponent
@end

@implementation CKTransactionalComponentDataSourceIntegrationTestComponent
+ (instancetype)newWithIdentifier:(id)identifier {
  CKComponentScope scope(self, identifier);
  return [self newWithComponent:[CKComponent new]];
}
@end

@interface CKTransactionalComponentDataSourceIntegrationTestComponentController : CKComponentController
@property (strong) NSMutableArray *callbacks;
@end

@implementation CKTransactionalComponentDataSourceIntegrationTestComponentController
- (instancetype)initWithComponent:(CKComponent *)component {
  if ((self = [super initWithComponent:component])) {
    self.callbacks = [NSMutableArray array];
  }
  return self;
}

- (void)willUpdateComponent {
  [super willUpdateComponent];
  [self.callbacks addObject:NSStringFromSelector(_cmd)];
}
- (void)willRemount {
  [super willRemount];
  [self.callbacks addObject:NSStringFromSelector(_cmd)];
}
- (void)didRemount {
  [super didRemount];
  [self.callbacks addObject:NSStringFromSelector(_cmd)];
}
- (void)didUpdateComponent {
  [super didUpdateComponent];
  [self.callbacks addObject:NSStringFromSelector(_cmd)];
}
- (void)invalidateController
{
  [super invalidateController];
  [self.callbacks addObject:NSStringFromSelector(_cmd)];
}
@end

@interface CKTransactionalComponentDataSourceIntegrationTests : XCTestCase
@property (strong) UICollectionViewController *collectionViewController;
@property (strong) CKCollectionViewTransactionalDataSource *dataSource;
@property (strong) NSMutableArray <CKComponent *> *components;
@property (strong) CKTransactionalComponentDataSourceIntegrationTestComponentController *componentController;
@end

@implementation CKTransactionalComponentDataSourceIntegrationTests

- (void)setUp {
  [super setUp];

  self.collectionViewController = [[UICollectionViewController alloc]
                                   initWithCollectionViewLayout:[UICollectionViewFlowLayout new]];

  CKTransactionalComponentDataSourceConfiguration *config = [[CKTransactionalComponentDataSourceConfiguration alloc]
                                                             initWithComponentProvider:(id) self
                                                             context:nil
                                                             sizeRange:CKSizeRange({50, 50}, {50, 50})];

  self.components = [NSMutableArray new];
  self.dataSource = [[CKCollectionViewTransactionalDataSource alloc]
                     initWithCollectionView:self.collectionViewController.collectionView
                     supplementaryViewDataSource:nil
                     configuration:config];

  [self.dataSource applyChangeset:
   [[[[CKTransactionalComponentDataSourceChangesetBuilder new]
      withInsertedSections:[NSIndexSet indexSetWithIndex:0]]
     withInsertedItems:@{ [NSIndexPath indexPathForItem:0 inSection:0] : @"" }]
    build] mode:CKUpdateModeSynchronous userInfo:nil];

  XCTAssertEqual(self.components.count, 1);
  XCTAssertNotNil(self.components.lastObject.controller);
  XCTAssertTrue([self.components.lastObject.controller isKindOfClass:[CKTransactionalComponentDataSourceIntegrationTestComponentController class]]);

  self.componentController =
  (CKTransactionalComponentDataSourceIntegrationTestComponentController*) self.components.lastObject.controller;
}

- (CKComponent *)componentForModel:(NSString*)model context:(id<NSObject>)context {
  CKComponent *component = [CKTransactionalComponentDataSourceIntegrationTestComponent newWithIdentifier:@"TestComponent"];
  [self.components addObject:component];
  return component;
}

- (void)testUpdateModelShouldCreateNewComponentAndTriggerControllerCallbacksForRemount {
  [self.dataSource applyChangeset:
   [[[CKTransactionalComponentDataSourceChangesetBuilder new]
     withUpdatedItems:@{[NSIndexPath indexPathForItem:0 inSection:0] : @""}]
    build] mode:CKUpdateModeSynchronous userInfo:nil];

  XCTAssertEqual(self.components.count, 2);
  XCTAssertEqualObjects(self.componentController.callbacks, (@[
                                                              NSStringFromSelector(@selector(willUpdateComponent)),
                                                              NSStringFromSelector(@selector(willRemount)),
                                                              NSStringFromSelector(@selector(didRemount)),
                                                              NSStringFromSelector(@selector(didUpdateComponent))
                                                              ]));
}

// This test checks that controller receives invalidateController callback when DataSource owning it
// applies change that removes it from the state
- (void)testComponentControllerReceivesInvalidateEventWhenRemoved
{
  [self.dataSource applyChangeset:
   [[[CKTransactionalComponentDataSourceChangesetBuilder new]
     withRemovedItems:[NSSet setWithObject:[NSIndexPath indexPathForItem:0 inSection:0]]]
    build] mode:CKUpdateModeSynchronous userInfo:nil];
  self.dataSource = nil;
  XCTAssertEqualObjects(self.componentController.callbacks, (@[
                                                               NSStringFromSelector(@selector(invalidateController)),
                                                               ]));
}

// This test checks that controller receives invalidateController callback when DataSource owning it is destroyed
- (void)testComponentControllerReceivesInvalidateEventDuringDeallocation
{
  NSArray *callbacks = nil;
  @autoreleasepool {
    CKTransactionalComponentDataSourceConfiguration *config = [[CKTransactionalComponentDataSourceConfiguration alloc]
                                                               initWithComponentProvider:(id) self
                                                               context:nil
                                                               sizeRange:CKSizeRange({50, 50}, {50, 50})];
    CKCollectionViewTransactionalDataSource *dataSource = [[CKCollectionViewTransactionalDataSource alloc]
                                                           initWithCollectionView:self.collectionViewController.collectionView
                                                           supplementaryViewDataSource:nil
                                                           configuration:config];
    self.dataSource = dataSource;
    
    [self.dataSource applyChangeset:
     [[[[CKTransactionalComponentDataSourceChangesetBuilder new]
        withInsertedSections:[NSIndexSet indexSetWithIndex:0]]
       withInsertedItems:@{ [NSIndexPath indexPathForItem:0 inSection:0] : @"" }]
      build] mode:CKUpdateModeSynchronous userInfo:nil];
    
    CKTransactionalComponentDataSourceIntegrationTestComponentController * controller =
      (CKTransactionalComponentDataSourceIntegrationTestComponentController*) self.components.lastObject.controller;
    callbacks = controller.callbacks;
    
    // We clean everything to ensure dataSource receives deallocation happens when autorelease pool is destroyed
    self.dataSource = nil;
    self.components = nil;
    self.componentController = nil;
    self.collectionViewController = nil;
  }
  XCTAssertEqualObjects(callbacks, (@[NSStringFromSelector(@selector(invalidateController))]));
}

@end
