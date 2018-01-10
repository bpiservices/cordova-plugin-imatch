//
//  GridleriMatch.h
//  Gridler iMatch Cordova Plugin
//


#ifndef SimpleSerial_GridleriMatch_h
#define SimpleSerial_GridleriMatch_h

#import <Cordova/CDV.h>
#import "BLE.h"

@interface GridleriMatch : CDVPlugin <BLEDelegate> {
    BLE *_bleShield;
    NSString* _connectCallbackId;
    NSString* _subscribeCallbackId;
    NSString* _rssiCallbackId;
    Byte *_buffer;
    int _bufferLen;
    NSString *_delimiter;
}

- (void)connect:(CDVInvokedUrlCommand *)command;
- (void)disconnect:(CDVInvokedUrlCommand *)command;

- (void)subscribe:(CDVInvokedUrlCommand *)command;
- (void)unsubscribe:(CDVInvokedUrlCommand *)command;
- (void)write:(CDVInvokedUrlCommand *)command;

- (void)list:(CDVInvokedUrlCommand *)command;
- (void)isEnabled:(CDVInvokedUrlCommand *)command;
- (void)isConnected:(CDVInvokedUrlCommand *)command;

- (void)available:(CDVInvokedUrlCommand *)command;
- (void)clear:(CDVInvokedUrlCommand *)command;

- (void)readRSSI:(CDVInvokedUrlCommand *)command;

@end

#endif