# cordova-plugin-imatch

Cordova plugin for the [BPI iMatch](https://www.bpiservices.eu/solutions/imatch/): a Bluetooth fingerprint, smartcard and ICAO document reader.

## Requirements

| | |
|---|---|
| Cordova CLI | 13 or newer |
| cordova-android | 15 or newer (target SDK 36, min SDK 24) |
| cordova-ios | 8 or newer, deployment target 14.4 or newer |
| iMatch SDK | supplied separately; iOS SDK 1.9.0 or newer |

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

All calls take `(...args, success, error)` callbacks. Every callback, success or error, receives a message object `{ method, data }`. Long-lived callbacks (`connect`, `setDisconnectHandler`, `setReceiveEventListener`, `scanFingerprint`, `scanPassport`, `update`) fire more than once.

`connect` answers with `{ method: 'connect', data: { connected: true } }` once the Bluetooth link is up, or calls the error callback when the connection fails or takes longer than 30 seconds. Later changes arrive on the same callback as `connectionchange`. Both carry `data.connected`, so checking that one field on every call is enough.

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
        iMatch.scanFingerprint('FLAT_TWO_FINGERS', false, 1, onFingerEvent, console.error, ['WSQ', 'PNG']);
    }
});

function onFingerEvent(msg) {
    switch (msg.method) {
        case 'fp_image':    /* msg.data.image is base64, msg.data.format is 'wsq' or 'png' */ break;
        case 'fp_nfiq':     /* quality score per finger */ break;
        case 'fp_finished': iMatch.powerOffFingerprint(true); break;
    }
}
```

`fp_finished` is the only reliable end-of-capture signal. Do not count NFIQ events.

The third argument selects the quality score: `0` none, `1` NFIQ 1 (1 best to 5 worst), `2` NFIQ 2 (0 worst to 100 best).
`true` and `false` still select NFIQ 1 and none. NFIQ 2 needs IBScan 1.3.0 or newer on the device; with an older
version the error callback gets code 998 and no capture starts. When the NFIQ 2 plugin is missing on the device, the
success callback gets a `warning` event instead of `fp_nfiq`. NFIQ 2 is not available on Android yet (error 501).

`setInstallNfiq2Plugin(true)` makes later `update` calls install the NFIQ 2 plugin on an iMatch 45/50 that does not
have it yet. It is about 5 MB and adds about 50 minutes to the update, so it is off by default. The iMatch needs
firmware 1.12.5.4 or newer to report whether the plugin is installed; the firmware update that `update` starts with
brings it there.

#### Timeout and cancel (iMatch 45/50, firmware 1.12.5.4 or newer)

The last argument of `scanFingerprint` is an optional capture timeout: the seconds the scanner may stay idle (no
finger activity) before the capture stops, up to 255; `0` or omitted means no timeout. Once the fingers are acquired
it no longer applies. When it expires, the error callback gets `{ method: 'error', data: 'Capture timeout' }`, usually
5 to 10 seconds later while the iMatch restarts the scanner. The reader stays powered on.

`cancelFingerprint(success, error)` stops a running capture, usually within 1 to 2 seconds. Its own callbacks only
say whether the request was sent; the error callback gets `Not connected`, or `Not supported` on an iMatch 20. The
result arrives on the `scanFingerprint` callback as a `cancel` event:

| `data` | Meaning |
|---|---|
| `'1'` | capture stopped, reader stays on; also sent when nothing was running |
| `'0'` | the stop failed and the reader was switched off; the next `scanFingerprint` powers it on |
| `''` | older firmware, the capture was not stopped |

Image data in transit is discarded and the `cancel` event can get lost, so do not wait for it indefinitely; a
fallback of about 25 seconds works. After an error other than `Capture timeout`, or a failed standby, wake up or
cancel, the next `scanFingerprint` powers the reader on again before it starts the capture.

### Documents (NFC)

```js
iMatch.scanPassport(mrzLine1 + '
' + mrzLine2, function (msg) {
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
| `list(success, error)` | `data` is an array of device names; error when Bluetooth is off |
| `connect(name, success, error)` | answers when the link is up; kept alive, also reports connection changes |
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
| `update(progress, error)` | progress until `completed`; needs a connected iMatch |
| `cancelUpdate(success)` | the `update` error callback gets the final event |
| `setInstallNfiq2Plugin(install, success, error)` | whether `update` installs the optional NFIQ 2 plugin; default `false` |
| `powerOnFingerprint`, `powerOffFingerprint(tryStandby)` | |
| `scanFingerprint(imageType, segmented, nfiqVersion, success, error, imageFormats?, timeoutSeconds?)` | iMatch 45/50; `nfiqVersion` 0, 1 or 2 (or `true`/`false`); `imageFormats` defaults to `['WSQ']`, one `fp_image` per format; `timeoutSeconds` 0 to 255 |
| `cancelFingerprint(success, error)` | iMatch 45/50; result as a `cancel` event on the `scanFingerprint` callback |
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
| `read_dg2` payload | `{ image }` as JPEG | `{ raw, image, mimeType, sourceMimeType }`; `image` is always JPEG (JPEG 2000 and PNG are decoded on the phone), `raw` is the data group as read |
| `read_sod`, other DGs | parsed | `{ raw }` base64 |
| `read_photo` (smartcard) | as delivered by the SDK | `{ raw, image, mimeType, sourceMimeType }`, `image` always JPEG |
| `validateComputedHashes` | passive authentication result | error, not available yet |
| NFIQ 2 (`nfiqVersion` 2) | supported, needs IBScan 1.3.0 or newer | error 501, not available yet |
| `setInstallNfiq2Plugin(true)` | supported | needs Android SDK 1.6.0 or newer, otherwise error `Not supported` |
| `access_control` event | `{ type, ... }` | `{ type, success, raw }` |
| Firmware update | SDK updater | main firmware, then the MP1 second stage on iMatch 45/50 |
