# cordova-plugin-imatch

Cordova plugin for the [BPI iMatch](https://www.bpiservices.eu/solutions/imatch/): a Bluetooth fingerprint, smartcard and ICAO document reader.

## Requirements

| | |
|---|---|
| Cordova CLI | 13 or newer |
| cordova-android | 15 or newer (target SDK 36, min SDK 24) |
| cordova-ios | 8 or newer, deployment target 14.4 or newer |
| iMatch SDK | supplied separately  |

## Install

The plugin is on npm, the native SDK binaries are not. Request the iMatch SDK from BPI Services.
It has this layout:

```
imatch-sdk/
├── sdk-version.json
├── android/imatchsdk.aar
└── ios/iMatchSDK.xcframework/
```

Unzip it into your Cordova project as `imatch-sdk/` (next to `config.xml`), then add the plugin:

```
cd my-app
unzip imatch-sdk-cordova-<version>.zip -d imatch-sdk
cordova plugin add cordova-plugin-imatch
```

During install the plugin copies the binaries for each platform from `imatch-sdk/` into itself, so the folder must stay in the project - `cordova prepare` on a fresh clone repeats the copy. A different location can be given with a plugin variable or an
environment variable:

```
cordova plugin add cordova-plugin-imatch --variable IMATCH_SDK_DIR=../shared/imatch-sdk
IMATCH_SDK_DIR=/opt/imatch-sdk cordova plugin add cordova-plugin-imatch
```

Set the iOS deployment target in your `config.xml`; the SDK needs at least 14.4:

```xml
<platform name="ios">
    <preference name="deployment-target" value="14.4" />
</platform>
```

The Bluetooth usage description shown to iOS users can be customised at install time:

```
cordova plugin add ./cordova-plugin-imatch --variable BLUETOOTH_USAGE_DESCRIPTION="..."
```

## Permissions

Android: the plugin declares the Bluetooth permissions and requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime on Android 12 and newer (location on older versions) the first time `list` is called.

iOS: `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` are added to the app's Info.plist by the plugin.

## Usage

All calls take `(...args, success, error)` callbacks. Every callback receives a message object `{ method, data }`. Long-lived callbacks (`connect`, `setDisconnectHandler`, `setReceiveEventListener`, `scanFingerprint`, `scanPassport`, `update`) fire more than once.

```js
document.addEventListener('deviceready', function () {
    iMatch.initialize();

    iMatch.setReceiveEventListener(function (event) {
        // event.method: info, status, fp_image, fp_finished, read_dg1, read_dg2, ...
        console.log(event.method, event.data);
    });

    iMatch.setDisconnectHandler(function () {
        console.log('iMatch disconnected');
    });

    iMatch.list(function (result) {
        var names = result.data;              // ["iMatch-1234", ...]
        iMatch.connect(names[0], function (msg) {
            if (msg.data.connected) {
                iMatch.needsUpdate(function (u) {
                    if (u.data.required) {
                        iMatch.update(function (p) { console.log(p.data.action, p.data.progress); });
                    }
                });
            }
        }, console.error);
    }, console.error);
});
```

### Fingerprints

```js
iMatch.hardwareVersion(function (hw) {
    if (hw.data === 'iMatch20') {
        iMatch.scanFingerprintFAP20(onFingerEvent, console.error);
    } else {
        iMatch.scanFingerprint('FLAT_TWO_FINGERS', false, true, onFingerEvent, console.error);
    }
});

function onFingerEvent(msg) {
    switch (msg.method) {
        case 'fp_image':    /* msg.data.image is base64 */ break;
        case 'fp_nfiq':     /* quality score per finger */ break;
        case 'fp_finished': iMatch.powerOffFingerprint(true); break;
    }
}
```

`fp_finished` is the only reliable end-of-capture signal. Do not count NFIQ events.

### Documents (NFC)

```js
iMatch.scanPassport(mrzLine1 + mrzLine2, function (msg) {
    // access_control, read_efcom, read_sod, read_dg1, read_dg2 (msg.data.image is a JPEG), ...
}, console.error);
```

### Smartcards

```js
iMatch.readSmartcard(function (msg) { /* read_card, read_id, read_person, read_photo, ... */ });
```

## API

| Method | Notes |
|---|---|
| `initialize(success, error)` | call once after `deviceready` |
| `list(success, error)` | `data` is an array of device names |
| `connect(name, success, error)` | kept alive, also reports connection changes |
| `disconnect(success, error)` | |
| `connected(success, error)` | |
| `setDisconnectHandler(handler)` | |
| `setReceiveEventListener(listener, error)` | all device notifications |
| `hardwareVersion(success, error)` | `iMatch20`, `iMatch45`, `iMatch50` |
| `requestDeviceInfo(success, error)` | firmware version, hardware |
| `requestStatus(success, error)` | battery state |
| `isCharging(success, error)` | last known charging state |
| `write(data, success, error)` | raw JSON-RPC message |
| `needsUpdate(success, error)` | |
| `update(progress, error)` | progress until `completed` |
| `cancelUpdate(success)` | |
| `powerOnFingerprint`, `powerOffFingerprint(tryStandby)` | |
| `scanFingerprint(imageType, segmented, calculateNFIQ, success, error)` | iMatch 45/50 |
| `scanFingerprintFAP20(success, error)` | iMatch 20 |
| `powerOnSmartcard`, `powerOffSmartcard`, `readSmartcard` | |
| `powerOnNFC`, `powerOffNFC`, `scanPassport(mrz, success, error)` | |
| `getEFCOMItems(success, error)` | data groups present on the chip |
| `validateComputedHashes(success, error)` | passive authentication result |

TypeScript declarations are in `types/imatch.d.ts`.

## Platform differences

The JS API is identical on both platforms; the depth of document processing is not yet.

| | iOS | Android |
|---|---|---|
| Access control, DG reading | on the phone via the iOS SDK (PACE, BAC, CA, AA) | on the iMatch via `mrtdread` (PACE with BAC fallback; chip authentication off in 2.0.0) |
| `read_dg1` payload | parsed MRZ fields | `{ raw, mrz }` |
| `read_dg2` payload | `{ image }` as JPEG | `{ raw, image, mimeType }`, image as found in the chip (JPEG, JP2 or PNG); decode JP2 with `cordova-plugin-jj2000` |
| `read_sod`, other DGs | parsed | `{ raw }` base64 |
| `validateComputedHashes` | passive authentication result | error, not available yet |
| `access_control` event | `{ type, ... }` | `{ type, success, raw }` |
| Firmware update | SDK updater | main firmware, then the MP1 second stage on iMatch 45/50 |
