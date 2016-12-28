#import "ViewController.h"  // Header
#import <PahoUI/PahoUI.h>   // PahoUI
#import <MQTT/MQTTClient.h> // MQTT
#import <MQTT/MQTTAsync.h>  // MQTT
#import "AjmideMessage.pbobjc.h"

#import "UIView+Toast.h"

@interface ViewController () <UITextFieldDelegate>
@property (weak,nonatomic) IBOutlet RLYTextField* brokerField;
@property (weak,nonatomic) IBOutlet RLYButton* brokerButton;
@property (weak,nonatomic) IBOutlet UIView* dataView;
@property (weak,nonatomic) IBOutlet RLYTextField* subscriptionField;
@property (weak,nonatomic) IBOutlet RLYButton* subscriptionButton;
@property (weak,nonatomic) IBOutlet RLYTextField* publishField;
@property (weak,nonatomic) IBOutlet RLYTextField* publishBodyField;
@property (weak,nonatomic) IBOutlet RLYButton* publishButton;

@property (unsafe_unretained,nonatomic) MQTTAsync mqttClient;
@property (strong,nonatomic) NSString* mqttClientID;
@property (strong,nonatomic) NSString* mqttUsername;
@property (strong,nonatomic) NSString* mqttPassword;
@end

#pragma mark - C Private prototypes
void mqttConnectionSucceeded(void* context, MQTTAsync_successData* response);
void mqttConnectionFailed(void* context, MQTTAsync_failureData* response);
void mqttConnectionLost(void* context, char* cause);

void mqttSubscriptionSucceeded(void* context, MQTTAsync_successData* response);
void mqttSubscriptionFailed(void* context, MQTTAsync_failureData* response);
int mqttMessageArrived(void* context, char* topicName, int topicLen, MQTTAsync_message* message);
void mqttUnsubscriptionSucceeded(void* context, MQTTAsync_successData* response);
void mqttUnsubscriptionFailed(void* context, MQTTAsync_failureData* response);

void mqttPublishSucceeded(void* context, MQTTAsync_successData* response);
void mqttPublishFailed(void* context, MQTTAsync_failureData* response);

void mqttDisconnectionSucceeded(void* context, MQTTAsync_successData* response);
void mqttDisconnectionFailed(void* context, MQTTAsync_failureData* response);

@implementation ViewController

#pragma mark - Public API

- (void)awakeFromNib
{
    _mqttClient = NULL;
    _mqttClientID = [NSString stringWithFormat:@"%@",[[NSUUID UUID] UUIDString]];
}

- (void)viewDidLoad
{
    [self resetUI];
}

#pragma mark - Private API

- (IBAction)brokerButtonPressed:(RLYButton*)sender
{
    int status;
    [self.view endEditing:YES];
    __weak ViewController* weakSelf = self;
    
    if (_mqttClient == NULL)
    {
        if (!_brokerField.text.length || !_mqttClientID.length) { return; }
        
        status = MQTTAsync_create(&_mqttClient, _brokerField.text.UTF8String, _mqttClientID.UTF8String, MQTTCLIENT_PERSISTENCE_NONE, NULL);
        if (status != MQTTASYNC_SUCCESS) { return; }
        
        status = MQTTAsync_setCallbacks(_mqttClient, (__bridge void*)weakSelf, mqttConnectionLost, mqttMessageArrived, NULL);
        if (status != MQTTASYNC_SUCCESS) { mqttDestroy((__bridge void*)weakSelf); }
        
        MQTTAsync_connectOptions connOptions = MQTTAsync_connectOptions_initializer;
        connOptions.onSuccess = mqttConnectionSucceeded;
        connOptions.onFailure = mqttConnectionFailed;
        connOptions.context = (__bridge void*)weakSelf;
        
        _brokerField.enabled = NO;
        [_brokerButton setTitle:@"Connecting" forState:UIControlStateDisabled];
        _brokerButton.enabled = NO;
        
        status = MQTTAsync_connect(_mqttClient, &connOptions);
        if (status != MQTTASYNC_SUCCESS) { mqttDestroy((__bridge void*)weakSelf); }
    }
    else
    {
        _brokerField.enabled = NO;
        [_brokerButton setTitle:@"Disconnecting" forState:UIControlStateDisabled];
        _brokerButton.enabled = NO;
        _dataView.hidden = YES;
        
        MQTTAsync_disconnectOptions disconnOptions = MQTTAsync_disconnectOptions_initializer;
        disconnOptions.onSuccess = mqttDisconnectionSucceeded;
        disconnOptions.onFailure = mqttDisconnectionFailed;
        disconnOptions.context = (__bridge void*)weakSelf;
        status = MQTTAsync_disconnect(_mqttClient, &disconnOptions);
    }
}

- (IBAction)subscribeButtonPressed:(RLYButton*)sender
{
    if (_mqttClient==NULL) { return; }
    if (!_subscriptionField.text.length) { printf("You need to write a subscription topic.\n"); return; }
    
    int status;
    [self.view endEditing:YES];
    __weak ViewController* weakSelf = self;
    
    if ([[_subscriptionButton titleForState:UIControlStateNormal] isEqualToString:@"Subscribe"])
    {   // When the button is pressed, you want to subscribe.
        _subscriptionField.enabled = NO;
        [_subscriptionButton setTitle:@"Subscribing" forState:UIControlStateDisabled];
        _subscriptionButton.enabled = NO;
        
        MQTTAsync_responseOptions subOptions = MQTTAsync_responseOptions_initializer;
        subOptions.onSuccess = mqttSubscriptionSucceeded;
        subOptions.onFailure = mqttSubscriptionFailed;
        subOptions.context = (__bridge void*)weakSelf;
        status = MQTTAsync_subscribe(_mqttClient, _subscriptionField.text.UTF8String, 0, &subOptions);
        if (status != MQTTASYNC_SUCCESS) { _subscriptionButton.enabled = YES; }
    }
    else
    {   // When the button is pressed, you want to unsubscribe
        [_subscriptionButton setTitle:@"Unsubscribing" forState:UIControlStateDisabled];
        _subscriptionButton.enabled = NO;
        
        MQTTAsync_responseOptions unsubOptions = MQTTAsync_responseOptions_initializer;
        unsubOptions.onSuccess = mqttUnsubscriptionSucceeded;
        unsubOptions.onFailure = mqttUnsubscriptionFailed;
        unsubOptions.context = (__bridge void*)weakSelf;
        status = MQTTAsync_unsubscribe(_mqttClient, _subscriptionField.text.UTF8String, &unsubOptions);
        if (status != MQTTASYNC_SUCCESS) { _subscriptionField.enabled = YES; _subscriptionButton.enabled = YES; }
    }
}

- (IBAction)publishButtonPressed:(RLYButton*)sender
{
    if (_mqttClient==NULL) { return; }
    if (!_publishField.text.length) { printf("You need to write a publish topic.\n"); return; }
    if (!_publishBodyField.text.length) { printf("You need to to write a message to be published.\n"); return; }
    
    __weak ViewController* weakSelf = self;
    [self.view endEditing:YES];
    
    CMDRequest* req = [[CMDRequest alloc]init];
    [req setAction:CMD_TYPE_CmdTypeNeedendlive];
    NSData* sendData = [req data];
    int type = 5;
    NSData *data = [NSData dataWithBytes: &type length: sizeof(type)];
    
    NSMutableData* sd = [NSMutableData data];
    [sd appendData:sendData];
    [sd appendData:data];
    
    
    
    MQTTAsync_message message = MQTTAsync_message_initializer;

    message.payload = (void*)[sd bytes];
    message.payloadlen = (int)[sd length];
    
    
    _publishButton.enabled = NO;
    _publishField.enabled = NO;
    
    MQTTAsync_responseOptions pubOptions = MQTTAsync_responseOptions_initializer;
    pubOptions.onSuccess = mqttPublishSucceeded;
    pubOptions.onFailure = mqttPublishFailed;
    pubOptions.context = (__bridge void*)weakSelf;
    int status = MQTTAsync_sendMessage(_mqttClient, _publishField.text.UTF8String, &message, &pubOptions);
    if (!status != MQTTASYNC_SUCCESS) { _publishField.enabled = YES; _publishButton.enabled = YES; }
}

#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    
    if (textField == _brokerField) {
        [self brokerButtonPressed:_brokerButton];
    } else if (textField == _subscriptionField) {
        [self subscribeButtonPressed:_subscriptionButton];
    } else if (textField == _publishField) {
        [_publishBodyField becomeFirstResponder];
    } else if (textField == _publishBodyField) {
        [self publishButtonPressed:_publishButton];
    }
    return YES;
}

#pragma mark UI methods

- (void)resetUI
{
    _brokerField.enabled = YES;
    [_brokerButton setTitle:@"Connect" forState:UIControlStateNormal];
    _brokerButton.enabled = YES;
    
    _dataView.hidden = YES;
    [_subscriptionButton setTitle:@"Subscribe" forState:UIControlStateNormal];
    _subscriptionButton.enabled = YES;
    [_publishButton setTitle:@"Publish" forState:UIControlStateNormal];
    _publishButton.enabled = YES;
}

#pragma mark MQTT functions

void mqttConnectionSucceeded(void* context, MQTTAsync_successData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        printf("MQTT connection to broker succeeded.\n");
        
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        strongSelf.brokerButton.enabled = YES;
        strongSelf.brokerButton.backgroundColor = strongSelf.brokerButton.selectedBackgroundColor;
        [strongSelf.brokerButton setTitle:@"Disconnect" forState:UIControlStateNormal];
        strongSelf.dataView.hidden = NO;
    });
}

void mqttConnectionFailed(void* context, MQTTAsync_failureData* response)
{
    printf("MQTT connection to broker failed.\n");
    mqttDestroy(context);
}

void mqttConnectionLost(void* context, char* cause)
{
    printf("MQTT connection was lost with cause: %s\n", cause);
    mqttDestroy(context);
}

void mqttSubscriptionSucceeded(void* context, MQTTAsync_successData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT subscription succeeded to topic: %s\n", strongSelf.subscriptionField.text.UTF8String);
        [strongSelf.subscriptionButton setTitle:@"Unsubscribe" forState:UIControlStateNormal];
        strongSelf.subscriptionButton.enabled = YES;
        strongSelf.subscriptionButton.backgroundColor = strongSelf.subscriptionButton.selectedBackgroundColor;
    });
}

void mqttSubscriptionFailed(void* context, MQTTAsync_failureData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT subscription failed to topic: %s", strongSelf.subscriptionField.text.UTF8String);
        strongSelf.subscriptionField.enabled = YES;
        [strongSelf.subscriptionButton setTitle:@"Subscribe" forState:UIControlStateNormal];
        strongSelf.subscriptionButton.enabled = YES;
    });
}

int mqttMessageArrived(void* context, char* topicName, int topicLen, MQTTAsync_message* message)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError* error = nil;
        NSData* data = [NSData dataWithBytes:message->payload length:message->payloadlen];
        int type;
        NSMutableData* rd = [NSMutableData dataWithData:data];
        NSData* typeData = [rd subdataWithRange:NSMakeRange(message->payloadlen-sizeof(type), sizeof(type))];
        
        [typeData getBytes: &type length: sizeof(type)];
        
        NSData* RealData = [rd subdataWithRange:NSMakeRange(0, message->payloadlen-sizeof(type))];
        
        
        CMDResponse* response = [CMDResponse parseFromData:RealData error:&error];
        
        printf("MQTT message arrived from topic: %s with body: %zi\n", topicName, response.action);
        
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        
        [strongSelf.view makeToast:[NSString stringWithCString:message->payload encoding:NSUTF8StringEncoding]];
    });
    return true;
}

void mqttUnsubscriptionSucceeded(void* context, MQTTAsync_successData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT unsubscription succeeded.\n");
        strongSelf.subscriptionField.enabled = YES;
        [strongSelf.subscriptionButton setTitle:@"Subscribe" forState:UIControlStateNormal];
        strongSelf.subscriptionButton.enabled = YES;
        strongSelf.subscriptionButton.backgroundColor = strongSelf.subscriptionButton.defaultBackgroundColor;
    });
}

void mqttUnsubscriptionFailed(void* context, MQTTAsync_failureData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT unsubscription failed.\n");
        strongSelf.subscriptionButton.enabled = YES;
    });
}

void mqttPublishSucceeded(void* context, MQTTAsync_successData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT publish message succeeded.\n");
        strongSelf.publishButton.enabled = YES;
        strongSelf.publishField.enabled = YES;
    });
}

void mqttPublishFailed(void* context, MQTTAsync_failureData* response)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        printf("MQTT publish message failed.\n");
        strongSelf.publishButton.enabled = YES;
        strongSelf.publishField.enabled = YES;
    });
}

void mqttDisconnectionSucceeded(void* context, MQTTAsync_successData* response)
{
    printf("MQTT disconnection succeeded.\n");
    mqttDestroy(context);
}

void mqttDisconnectionFailed(void* context, MQTTAsync_failureData* response)
{
    printf("MQTT disconnection failed.\n");
    mqttDestroy(context);
}

void mqttDestroy(void* context)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        printf("MQTT handler destroyed.\n");
        
        ViewController* strongSelf = (__bridge __weak ViewController*)context;
        if (!strongSelf) { return; }
        
        MQTTAsync mqttClient = strongSelf.mqttClient;
        MQTTAsync_destroy(&mqttClient);
        strongSelf.mqttClient = NULL;
        [strongSelf resetUI];
    });
}

@end
