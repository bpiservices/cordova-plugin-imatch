//
//  GridleriMatch.m
//  Gridler iMatch Cordova Plugin
//

#import "GridleriMatch.h"
#import <Cordova/CDV.h>

@interface GridleriMatch()
- (NSMutableArray *)getPeripheralList;
- (CBPeripheral *)findPeripheralByUUID:(NSString *)uuid;
- (void)connectToUUID:(NSString *)uuid;
- (void)listPeripheralsTimer:(NSTimer *)timer;
- (void)connectFirstDeviceTimer:(NSTimer *)timer;
- (void)connectUuidTimer:(NSTimer *)timer;
@end

@implementation GridleriMatch

- (void)pluginInitialize {

    NSLog(@"Gridler iMatch Cordova Plugin - BLE version");
    NSLog(@"(c)2018 Gridler");

    [super pluginInitialize];

    _bleShield = [[BLE alloc] init];
    [_bleShield controlSetup];
    [_bleShield setDelegate:self];

    _bufferLen = 0;
    _buffer = (Byte*)malloc(20480);
}

#pragma mark - Cordova Plugin Methods

- (void)connect:(CDVInvokedUrlCommand *)command {

    NSLog(@"connect");
    NSString *uuid = [command.arguments objectAtIndex:0];

    // if the uuid is null or blank, scan and
    // connect to the first available device

    if (uuid == (NSString*)[NSNull null]) {
        [self connectToFirstDevice];
    } else if ([uuid isEqualToString:@""]) {
        [self connectToFirstDevice];
    } else {
        [self connectToUUID:uuid];
    }

    _connectCallbackId = [command.callbackId copy];
}

- (void)disconnect:(CDVInvokedUrlCommand*)command {

    NSLog(@"disconnect");

    _connectCallbackId = nil;
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];

    if (_bleShield.activePeripheral) {
        if(_bleShield.activePeripheral.state == CBPeripheralStateConnected)
        {
            [[_bleShield CM] cancelPeripheralConnection:[_bleShield activePeripheral]];
        }
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)subscribe:(CDVInvokedUrlCommand*)command {
    NSLog(@"subscribe");

    _subscribeCallbackId = [command.callbackId copy];
}

- (void)unsubscribe:(CDVInvokedUrlCommand*)command {
    NSLog(@"unsubscribe");

    _subscribeCallbackId = nil;

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)write:(CDVInvokedUrlCommand*)command {
    NSLog(@"write");

    CDVPluginResult *pluginResult = nil;
    NSData *data  = [command.arguments objectAtIndex:0];

    if (data != nil) {
        NSMutableData *packet = [[NSMutableData alloc] init];
        
        uint8_t len1 = data.length & 0xFF;
        uint8_t len2 = data.length >> 8;
        const char header[] = { 0x01,len1,len2,0x02 };

        [packet appendBytes:header length:4];
        [packet appendData:data];
        
        int LRC = 0;

        unsigned char *bytes = [data bytes];
        for (int i = 0; i < data.length; i++)
        {
            LRC+=(int)bytes[i];
        }
        LRC = ((LRC & 0xFF) ^ 0xFF) + 1;

        const char eop[] = { 0x03,(uint8_t)LRC,0x04 };

        [packet appendBytes:eop length:3];
        NSData *immutableData = [NSData dataWithData:packet];
        [_bleShield write:immutableData];

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"data was null"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)list:(CDVInvokedUrlCommand*)command {

    [self scanForBLEPeripherals:3];

    [NSTimer scheduledTimerWithTimeInterval:(float)3.0
                                     target:self
                                   selector:@selector(listPeripheralsTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];
}

- (void)isEnabled:(CDVInvokedUrlCommand*)command {

    // short delay so CBCentralManger can spin up bluetooth
    [NSTimer scheduledTimerWithTimeInterval:(float)0.2
                                     target:self
                                   selector:@selector(bluetoothStateTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];

}

- (void)isConnected:(CDVInvokedUrlCommand*)command {

    CDVPluginResult *pluginResult = nil;

    if (_bleShield.isConnected) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not connected"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)available:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:_bufferLen];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)clear:(CDVInvokedUrlCommand*)command {
    [self clearBuffer];
}

- (void)readRSSI:(CDVInvokedUrlCommand*)command {
    NSLog(@"readRSSI");

    _rssiCallbackId = [command.callbackId copy];
    [_bleShield readRSSI];
}

#pragma mark - BLEDelegate

- (void)bleDidReceiveData:(unsigned char *)data length:(int)length {
    NSLog(@"bleDidReceiveData %d bytes", length);
    for (int i = 0; i < length; i++)
    {
        // Prevent restart of parsing because of 0x01 in header
        // (2nd byte length)
        if(data[i]==1 && _bufferLen>4) {
            // prevent checksum causing invalid new start so
            // check for absence of ETX
            if(_buffer[_bufferLen-1] != 3) {
                // clear the buffer
                free(_buffer);
                _buffer = (Byte*)malloc(20480);
            }
        }
        memcpy(_buffer+_bufferLen, &data[i], 1);
        _bufferLen++;
        // check for EOP byte 0x04
        // prevent early out because of 0x04 in header
        if(data[i]==4 && _bufferLen>4)
        {
            // Double check to prevent early out because of 4 in
            // checksum. So check presence of ETX
            if(_buffer[_bufferLen-3] != 3) {
                continue;
            }
            // len currently unused -- todo add verification for correct lenght
            int len = _buffer[2] << 8;
            len += _buffer[1];
            
            int json_len = _bufferLen-7;
            if(json_len>=0) {
                NSData *jsonRaw = [NSData dataWithBytesNoCopy:_buffer+4 length:json_len freeWhenDone:false];
                NSString *json = [[NSString alloc] initWithData:jsonRaw encoding:NSUTF8StringEncoding];
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:json];
                [pluginResult setKeepCallbackAsBool:TRUE];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:_subscribeCallbackId];
            }
            // clear the buffer
            free(_buffer);
            _buffer = (Byte*)malloc(20480);
            _bufferLen = 0;
        }
    }
}

- (void)bleDidConnect {
    NSLog(@"bleDidConnect");
    CDVPluginResult *pluginResult = nil;
    [self clearBuffer];

    if (_connectCallbackId) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_connectCallbackId];
    }
}

- (void)bleDidDisconnect {
    // TODO is there anyway to figure out why we disconnected?
    NSLog(@"bleDidDisconnect");

    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Disconnected"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_connectCallbackId];

    _connectCallbackId = nil;
}

- (void)bleDidUpdateRSSI:(NSNumber *)rssi {
    if (_rssiCallbackId) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[rssi doubleValue]];
        [pluginResult setKeepCallbackAsBool:TRUE]; // TODO let expire, unless watching RSSI
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_rssiCallbackId];
    }
}

#pragma mark - timers

-(void)listPeripheralsTimer:(NSTimer *)timer {
    NSString *callbackId = [timer userInfo];
    NSMutableArray *peripherals = [self getPeripheralList];

    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: peripherals];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

-(void)connectFirstDeviceTimer:(NSTimer *)timer {

    if(_bleShield.peripherals.count > 0) {
        NSLog(@"Connecting");
        [_bleShield connectPeripheral:[_bleShield.peripherals objectAtIndex:0]];
    } else {
        NSString *error = @"Did not find any BLE peripherals";
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_connectCallbackId];
    }
}

-(void)connectUuidTimer:(NSTimer *)timer {

    NSString *uuid = [timer userInfo];

    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];

    if (peripheral) {
        [_bleShield connectPeripheral:peripheral];
    } else {
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_connectCallbackId];
    }
}

- (void)bluetoothStateTimer:(NSTimer *)timer {

    NSString *callbackId = [timer userInfo];
    CDVPluginResult *pluginResult = nil;

    int bluetoothState = [[_bleShield CM] state];

    BOOL enabled = bluetoothState == CBCentralManagerStatePoweredOn;

    if (enabled) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:bluetoothState];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

#pragma mark - internal implemetation

- (NSMutableArray*) getPeripheralList {

    NSMutableArray *peripherals = [NSMutableArray array];

    for (int i = 0; i < _bleShield.peripherals.count; i++) {
        NSMutableDictionary *peripheral = [NSMutableDictionary dictionary];
        CBPeripheral *p = [_bleShield.peripherals objectAtIndex:i];

        NSString *uuid = p.identifier.UUIDString;
        [peripheral setObject: uuid forKey: @"uuid"];
        [peripheral setObject: uuid forKey: @"id"];

        NSString *name = [p name];
        if (!name) {
            name = [peripheral objectForKey:@"uuid"];
        }
        [peripheral setObject: name forKey: @"name"];

        NSNumber *rssi = [p btsAdvertisementRSSI];
        if (rssi) { // BLEShield doesn't provide advertised RSSI
            [peripheral setObject: rssi forKey:@"rssi"];
        }

        [peripherals addObject:peripheral];
    }

    return peripherals;
}

- (void)scanForBLEPeripherals:(int)timeout {

    NSLog(@"Scanning for BLE Peripherals");

    // disconnect
    if (_bleShield.activePeripheral) {
        if(_bleShield.activePeripheral.state == CBPeripheralStateConnected)
        {
            [[_bleShield CM] cancelPeripheralConnection:[_bleShield activePeripheral]];
            return;
        }
    }

    // remove existing peripherals
    if (_bleShield.peripherals) {
        _bleShield.peripherals = nil;
    }

    [_bleShield findBLEPeripherals:timeout];
}

- (void)connectToFirstDevice {

    [self scanForBLEPeripherals:3];

    [NSTimer scheduledTimerWithTimeInterval:(float)3.0
                                     target:self
                                   selector:@selector(connectFirstDeviceTimer:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)connectToUUID:(NSString *)uuid {

    int interval = 0;

    if (_bleShield.peripherals.count < 1) {
        interval = 3;
        [self scanForBLEPeripherals:interval];
    }

    [NSTimer scheduledTimerWithTimeInterval:interval
                                     target:self
                                   selector:@selector(connectUuidTimer:)
                                   userInfo:uuid
                                    repeats:NO];
}

- (CBPeripheral*)findPeripheralByUUID:(NSString*)uuid {

    NSMutableArray *peripherals = [_bleShield peripherals];
    CBPeripheral *peripheral = nil;

    for (CBPeripheral *p in peripherals) {

        NSString *other = p.identifier.UUIDString;

        if ([uuid isEqualToString:other]) {
            peripheral = p;
            break;
        }
    }
    return peripheral;
}

- (void)clearBuffer {
    free(_buffer);
    _buffer = (Byte*)malloc(20480);
    _bufferLen = 0;
}

@end