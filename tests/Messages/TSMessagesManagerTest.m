//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <XCTest/XCTest.h>

#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "Cryptography.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeContactsUpdater.h"
#import "OWSFakeNetworkManager.h"
#import "OWSMessageSender.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSGroupThread.h"
#import "TSMessagesManager.h"
#import "TSNetworkManager.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSMessagesManager (Testing)

// private method we are testing
- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)messageEnvelope
               withSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage;

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)messageEnvelope
               withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage;

@end

@interface OWSFakeMessageSender : OWSMessageSender

@property (nonatomic, readonly) XCTestExpectation *expectation;

@end

@implementation OWSFakeMessageSender

- (instancetype)initWithExpectation:(XCTestExpectation *)expectation
{
    self = [self init];
    if (!self) {
        return self;
    }

    _expectation = expectation;

    return self;
}

- (void)sendTemporaryAttachmentData:(NSData *)attachmentData
                        contentType:(NSString *)contentType
                          inMessage:(TSOutgoingMessage *)outgoingMessage
                            success:(void (^)())successHandler
                            failure:(void (^)(NSError *error))failureHandler
{

    NSLog(@"Faking sendTemporyAttachmentData.");
    [self.expectation fulfill];
    successHandler();
}

@end

@interface TSMessagesManagerTest : XCTestCase

@end

@implementation TSMessagesManagerTest

- (TSMessagesManager *)messagesManagerWithSender:(OWSMessageSender *)messageSender
{
    return [[TSMessagesManager alloc] initWithNetworkManager:[OWSFakeNetworkManager new]
                                              storageManager:[TSStorageManager sharedManager]
                                             contactsManager:[OWSFakeContactsManager new]
                                             contactsUpdater:[OWSFakeContactsUpdater new]
                                               messageSender:messageSender];
}

- (void)testIncomingSyncContactMessage
{
    XCTestExpectation *messageWasSent = [self expectationWithDescription:@"message was sent"];
    TSMessagesManager *messagesManager =
        [self messagesManagerWithSender:[[OWSFakeMessageSender alloc] initWithExpectation:messageWasSent]];

    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];
    OWSSignalServiceProtosSyncMessageBuilder *messageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    OWSSignalServiceProtosSyncMessageRequestBuilder *requestBuilder =
        [OWSSignalServiceProtosSyncMessageRequestBuilder new];
    [requestBuilder setType:OWSSignalServiceProtosSyncMessageRequestTypeGroups];
    [messageBuilder setRequest:[requestBuilder build]];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withSyncMessage:[messageBuilder build]];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     NSLog(@"No message submitted.");
                                 }];
}

- (void)testGroupUpdate
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];

    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];

    OWSSignalServiceProtosGroupContextBuilder *groupContextBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = OWSSignalServiceProtosGroupContextTypeUpdate;

    OWSSignalServiceProtosDataMessageBuilder *messageBuilder = [OWSSignalServiceProtosDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group Name", groupThread.name);
}

- (void)testGroupUpdateWithAvatar
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];


    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];

    OWSSignalServiceProtosGroupContextBuilder *groupContextBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = OWSSignalServiceProtosGroupContextTypeUpdate;

    OWSSignalServiceProtosAttachmentPointerBuilder *attachmentBuilder =
        [OWSSignalServiceProtosAttachmentPointerBuilder new];
    attachmentBuilder.id = 1234;
    attachmentBuilder.contentType = @"image/png";
    attachmentBuilder.key = [NSData new];
    attachmentBuilder.size = 123;
    groupContextBuilder.avatar = [attachmentBuilder build];

    OWSSignalServiceProtosDataMessageBuilder *messageBuilder = [OWSSignalServiceProtosDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group with Avatar Name", groupThread.name);
}

- (void)testUnknownGroupMessageIsIgnored
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupIdData:groupIdData];

    // Sanity check
    XCTAssertEqual(0, groupThread.numberOfInteractions);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];

    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];

    OWSSignalServiceProtosGroupContextBuilder *groupContextBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;

    // e.g. some future feature sent from another device that we don't yet support.
    groupContextBuilder.type = 666;

    OWSSignalServiceProtosDataMessageBuilder *messageBuilder = [OWSSignalServiceProtosDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    XCTAssertEqual(0, groupThread.numberOfInteractions);
}

@end

NS_ASSUME_NONNULL_END
