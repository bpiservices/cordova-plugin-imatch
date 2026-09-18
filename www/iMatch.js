var exec = require('cordova/exec');

var SERVICE = 'iMatch';

function call(action, args, success, error) {
    exec(success || null, error || null, SERVICE, action, args || []);
}

var iMatch = {
    // Lifecycle
    initialize: function (success, error) { call('initialize', [], success, error); },
    list: function (success, error) { call('list', [], success, error); },
    connect: function (deviceName, success, error) { call('connect', [deviceName], success, error); },
    disconnect: function (success, error) { call('disconnect', [], success, error); },
    connected: function (success, error) { call('connected', [], success, error); },
    setDisconnectHandler: function (handler) { call('setDisconnectHandler', [], handler, null); },
    setReceiveEventListener: function (listener, error) { call('setReceiveEventListener', [], listener, error); },

    // Device
    hardwareVersion: function (success, error) { call('hardwareVersion', [], success, error); },
    requestDeviceInfo: function (success, error) { call('requestDeviceInfo', [], success, error); },
    requestStatus: function (success, error) { call('requestStatus', [], success, error); },
    isCharging: function (success, error) { call('isCharging', [], success, error); },
    write: function (data, success, error) { call('write', [data], success, error); },

    // Firmware
    needsUpdate: function (success, error) { call('needsUpdate', [], success, error); },
    update: function (progress, error) { call('update', [], progress, error); },
    cancelUpdate: function (success) { call('cancelUpdate', [], success, null); },

    // Fingerprint reader
    powerOnFingerprint: function (success, error) { call('powerOnFingerprint', [], success, error); },
    powerOffFingerprint: function (tryStandby, success, error) { call('powerOffFingerprint', [!!tryStandby], success, error); },
    scanFingerprint: function (imageType, segmented, calculateNFIQ, success, error) {
        call('scanFingerprint', [imageType, !!segmented, !!calculateNFIQ], success, error);
    },
    scanFingerprintFAP20: function (success, error) { call('scanFingerprintFAP20', [], success, error); },

    // Smartcard reader
    powerOnSmartcard: function (success, error) { call('powerOnSmartcard', [], success, error); },
    powerOffSmartcard: function (success, error) { call('powerOffSmartcard', [], success, error); },
    readSmartcard: function (success, error) { call('readSmartcard', [], success, error); },

    // NFC reader
    powerOnNFC: function (success, error) { call('powerOnNFC', [], success, error); },
    powerOffNFC: function (success, error) { call('powerOffNFC', [], success, error); },
    scanPassport: function (mrz, success, error) { call('scanPassport', [mrz], success, error); },
    getEFCOMItems: function (success, error) { call('getEFCOMItems', [], success, error); },
    validateComputedHashes: function (success, error) { call('validateComputedHashes', [], success, error); }
};

module.exports = iMatch;
