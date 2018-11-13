/*global cordova*/
module.exports = {
    iMatchCmdId: 0,

    connect: function (macAddress, success, failure) {
        cordova.exec(success, failure, "iMatch", "connect", [macAddress]);
    },

    disconnect: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "disconnect", []);
    },

    // list bound devices
    list: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "list", []);
    },

    isEnabled: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "isEnabled", []);
    },

    isConnected: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "isConnected", []);
    },

    // the number of bytes of data available to read is passed to the success function
    available: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "available", []);
    },

    // writes data to the bluetooth serial port
    // data can be an ArrayBuffer, string, integer array, or Uint8Array
    write: function (data, success, failure) {
        // increment the command id and append it to the message
        this.iMatchCmdId++;
        var message = data;
        if (message.constructor !== {}.constructor)
        {
            message = JSON.parse(data);
        }
        message.id = this.iMatchCmdId;
        data = JSON.stringify(message);

        // convert to ArrayBuffer
        if (typeof data === 'string') {
            data = this.stringToArrayBuffer(data);
        } else if (data instanceof Array) {
            // assuming array of interger
            data = new Uint8Array(data).buffer;
        } else if (data instanceof Uint8Array) {
            data = data.buffer;
        }

        cordova.exec(success, failure, "iMatch", "write", [data]);
    },

    // calls the success callback when new data is available with an ArrayBuffer
    subscribe: function (success, failure) {
        successWrapper = function(data) {
            success(data);
        };
        cordova.exec(successWrapper, failure, "iMatch", "subscribe", []);
    },

    // removes data subscription
    unsubscribe: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "unsubscribe", []);
    },

    // clears the data buffer
    clear: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "clear", []);
    },

    // reads the RSSI of the *connected* peripherial
    readRSSI: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "readRSSI", []);
    },

    showBluetoothSettings: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "showBluetoothSettings", []);
    },

    enable: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "enable", []);
    },

    discoverUnpaired: function (success, failure) {
        cordova.exec(success, failure, "iMatch", "discoverUnpaired", []);
    },

    setDeviceDiscoveredListener: function (notify) {
        if (typeof notify != 'function')
            throw 'iMatch.setDeviceDiscoveredListener: Callback not a function';

        cordova.exec(notify, null, "iMatch", "setDeviceDiscoveredListener", []);
    },

    clearDeviceDiscoveredListener: function () {
        cordova.exec(null, null, "iMatch", "clearDeviceDiscoveredListener", []);
    },

    setName: function (newName) {
        cordova.exec(null, null, "iMatch", "setName", [newName]);
    },

    setDiscoverable: function (discoverableDuration) {
        cordova.exec(null, null, "iMatch", "setDiscoverable", [discoverableDuration]);
    },

    stringToArrayBuffer: function(str) {
        var ret = new Uint8Array(str.length);
        for (var i = 0; i < str.length; i++) {
            ret[i] = str.charCodeAt(i);
        }
        return ret.buffer;
    },
}