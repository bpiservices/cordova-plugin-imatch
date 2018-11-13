# cordova-plugin-imatch
Cordova plugin for the [Gridler iMatch](http://www.gridler.com/).

## Install
Install plugin:
```
cordova plugin add cordova-plugin-imatch
```

## Usage
Check if Bluetooth is enabled on the device:
```
iMatch.isEnabled(
    <<bluetooth is enabled>>,
    <<bluetooth is not enabled>
);
```

List all iMatch devices in range:
```
iMatch.list(
    function(results) {
        for (var i in results){
            console.log('found ID ' + results[i].id);
        }
    },
    function(error) {
        console.log(JSON.stringify(error));
    }
);
```

Connect to the iMatch device:
```
iMatch.connect(
    macAddress,                // macadresses as found with iMatch.list
    <<connection succeeded>>,  // i.e. start listening for messages
    <<connection error>>       // show the error if you fail
);
```

Subscribe to new message callback:
```
iMatch.subscribe(function (data) {
    try {
            var imatchMessage = JSON.parse(data);
            console.log('device: ' + imatchMessage.device + ' method:' + imatchMessage.method + ' data:' + imatchMessage.data);
        } catch(e) {
            console.log('error parsing ' + data + ' error: ' + e);
        }        
});
```

Write message to the iMatch device:
```
iMatch.write({imatch: "1.0", device: "sys", method: "datetime", params: "(2018, 1, 5, 5, 13, 31, 6, 0)", id: "1"});
```

Disconnect from the iMatch device:
```
iMatch.disconnect(
    app.closePort,     // stop listening for messages
    app.showError      // show the error if you fail
);
```

## Message protocol
See the [Wiki](https://github.com/Gridler/cordova-plugin-imatch/wiki/JSON-RPC-Protocol) for more information about the message protocol and all available commands.
