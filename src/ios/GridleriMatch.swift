import iMatchSDK

@objc(GridleriMatch) class GridleriMatch : CDVPlugin, iMatchManagerDelegate, iMatchDelegate, iMatchFingerprintDelegate, iMatchSmartcardDelegate, iMatchNFCDelegate {
    
    var callbackId: String = "";
    var smartcardCallbackId: String = "";
    var fingerprintCallbackId: String = "";
    var nfcCallbackId: String = "";
    var deviceCallbackId: String = "";
    var listCallbackId: String = "";
    var connectCallbackId: String = "";
    var disconnectCallbackId: String = "";
    var requestStatusCallbackId: String = "";
    var requestDeviceInfoCallbackId: String = "";
    var lastInfoMessage: [String:Any] = [:];
    
    var imatchDeviceName: String!
    var im: iMatchManager!
    var imatchDevice: iMatchDevice!
    var fingerprintReader: iMatchFingerprintReader!
    var smartcardReader: iMatchSmartcardReader!

    var imageType = ImageType.FLAT_TWO_FINGERS
    var segmentedFingers : Bool = true
    var calculateNFIQScore : Bool = true
    var nfcReader: iMatchNFCReader!
    var mrzkey: String = ""
    
    var sod: Sod?
    var efcom: EFCom?
    var dg1: EFDataGroup1?
    var dg14: EFDataGroup14?
    var dg15: EFDataGroup15?
    
    var updater: iMatchUpdater?
    var isUpdating = false;
    
    private var accessControl: String?
    private var allowedDatagroups: [MRTDtag]?
    private var lastChargingState: Bool = false
    
    func reset() {
        self.sod = nil
        self.efcom = nil
        self.dg1 = nil
        self.dg14 = nil
        self.dg15 = nil
        self.mrzkey = ""
        self.lastInfoMessage = [:]
        self.callbackId = "";
        self.smartcardCallbackId = "";
        self.fingerprintCallbackId = "";
        self.nfcCallbackId = "";
        self.listCallbackId = "";
        self.requestStatusCallbackId = "";
        self.requestDeviceInfoCallbackId = "";
        self.isUpdating = false;
    }

    @objc(initialize:) func initialize(command: CDVInvokedUrlCommand) {
        self.callbackId = command.callbackId;
        self.im = iMatchManager.getInstance()
        self.im.setDelegate(self)
        self.im.verbose = true
        self.updater = iMatchUpdater()
        
        sendPluginResult(message: createMessage(method: "initialize"), callback: self.callbackId);
    }

    @objc(list:) func list(command: CDVInvokedUrlCommand) {
        print("Listing iMatch devices")
        self.listCallbackId = command.callbackId;
        self.im = iMatchManager.getInstance()
        self.im.scan()
    }

    @objc(connect:) func connect(command: CDVInvokedUrlCommand) {
        print("Connecting")
        self.connectCallbackId = command.callbackId
        self.imatchDeviceName = command.arguments[0] as? String
        print("Connecting to: " + self.imatchDeviceName)

        self.imatchDevice = iMatchDevice.getInstance()
        self.imatchDevice.addDelegate(device: Device.Board, delegate: self)
        self.imatchDevice.addDelegate(device: Device.NfcReader, delegate: self)
        let connected = self.imatchDevice.connect(self.imatchDeviceName)

        if connected {
            let message = createMessage(method: "connect", data: ["connected" : true])
            sendPluginResult(message: message, callback: self.connectCallbackId);
        } else {
            let message = createMessage(method: "connect", data: ["connected" : false, "message": "Connection failed"])
            sendPluginResult(message: message, callback: self.connectCallbackId, ok: false);
        }
        self.reset()
    }

    @objc(disconnect:) func disconnect(command: CDVInvokedUrlCommand) {
        self.disconnectCallbackId = command.callbackId;
        if (self.imatchDevice.connected()) {
            self.imatchDevice.disconnect()
        } else {
            self.didDisconnect()
        }
    }
    
    func getArgumentAsBool(command: CDVInvokedUrlCommand, index:Int) -> Bool {
        let obj = command.arguments[index]
        if (obj is String) {
            let arg = obj as? String ?? ""
            return  ["true", "1"].contains(arg.lowercased())
        } else if (obj is Bool) {
            return (obj as? Bool) ?? false
        }
        return false
    }

    @objc(setDisconnectHandler:) func setDisconnectHandler(command: CDVInvokedUrlCommand) {
        self.disconnectCallbackId = command.callbackId;
    }

    @objc(isCharging:) func isCharging(command: CDVInvokedUrlCommand) {
        let message = createMessage(method: "ischarging", data: ["charging": self.lastChargingState])
        sendPluginResult(message: message, callback: command.callbackId)
    }
    
    @objc(needsUpdate:) func needsUpdate(command: CDVInvokedUrlCommand) {
        let needsUpdate = (self.updater?.needsUpdate())! || !self.isFirmwareSupported()
        let message = self.createMessage(method: "needsupdate", data: ["required": needsUpdate, "version" : self.updater?.version()]);
        self.sendPluginResult(message: message, callback: command.callbackId);
    }
    
    @objc(update:) func update(command: CDVInvokedUrlCommand) {
        if (self.isUpdating) {
            let message = self.createMessage(method: "update", data: ["error": "update in progress"]);
            self.sendPluginResult(message: message, callback: command.callbackId, ok: false);
            return;
        }
        
        self.isUpdating = true;
        var step: Int = -1;
        self.updater?.update(forceUpdate: false) { status in
            switch status {
            case .success(let progress):
                if (step != Int(progress.progress) || progress.completed) {
                    step = Int(progress.progress)
                    let message = self.createMessage(method: "update", data: [
                        "progress": Int(progress.progress),
                        "action": progress.action.toString(),
                        "completed": progress.completed
                    ]);
                    self.sendPluginResult(message: message, callback: command.callbackId);
                }
                
                if (progress.completed) {
                    self.isUpdating = false;
                }
                
                break
            case .failure(let error):
                let message = self.createMessage(method: "update", data: ["error": error.toString()]);
                self.sendPluginResult(message: message, callback: command.callbackId, ok: false);
                
                self.isUpdating = false;

                break
            }
        }
    }
    
    @objc(cancelUpdate:) func cancelUpdate(command: CDVInvokedUrlCommand) {
        self.updater?.cancel();
        
        self.isUpdating = false;
        
        let message = createMessage(method: "cancel_update");
        sendPluginResult(message: message, callback: command.callbackId);
    }

    @objc(setReceiveEventListener:) func setReceiveEventListener(command: CDVInvokedUrlCommand) {
        self.deviceCallbackId = command.callbackId
    }

    @objc(connected:) func connected(command: CDVInvokedUrlCommand) {
        self.callbackId = command.callbackId;

        let device = iMatchDevice.getInstance()
        let isConnected = device.connected()

        let message = createMessage(method: "connected", data: ["connected" : isConnected])
        sendPluginResult(message: message, callback: self.callbackId, ok: isConnected);
    }
        
    @objc(write:) func write(command: CDVInvokedUrlCommand) {
        print("Writing")
        
        let dataString = command.arguments[0] as! String
        let data = Data(dataString.utf8)

        self.imatchDevice = iMatchDevice.getInstance()

        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
            let deviceString = json["device"] as! String
            let methodString = json["method"] as! String
            let params = json["params"] as! String

            let device = Device(rawValue: deviceString) ?? .None
            let method = Method(rawValue: methodString) ?? .NONE

            self.imatchDevice.send(device: device, method: method, param: params)
            let message = createMessage(method: "write")
            sendPluginResult(message: message, callback: command.callbackId, keep: false);
        } catch let error as NSError {
            print("Failed to write: \(error.localizedDescription)")
            let message = createMessage(method: "write", data: ["code" : error.code, "message" : error.localizedDescription])
            sendPluginResult(message: message, callback: command.callbackId, ok: false, keep: false);
        }
    }

    private func fingerprintReaderCanSleep() -> Bool {
        let hardware = imatchDevice.getHardwareVersion()
        return hardware == Hardware.iMatch45 || hardware == Hardware.iMatch50
    }
    @objc(powerOnFingerprint:) func powerOnFingerprint(command: CDVInvokedUrlCommand) {
        self.fingerprintCallbackId = command.callbackId;
        self.fingerprintReader = iMatchFingerprintReader.getInstance()

        print("Powering on fingerprint reader", self.fingerprintReader.getState().rawValue);

        if (fingerprintReaderCanSleep() && self.fingerprintReader.getState() == FingerprintReaderState.STAND_BY) {
            self.fingerprintReader.wakeUp()
        } else if (self.fingerprintReader.getState() != FingerprintReaderState.ON){
            self.fingerprintReader.powerOn()
        }

        let message = createMessage(method: "poweron finger")
        sendPluginResult(message: message, callback: self.fingerprintCallbackId);
    }

    @objc(powerOffFingerprint:) func powerOffFingerprint(command: CDVInvokedUrlCommand) {
        print("Powering off fingerprint reader")
        var tryStandby = false;

        if (command.arguments.count > 0) {
            tryStandby = getArgumentAsBool(command: command, index: 0)
        }

        self.fingerprintReader = iMatchFingerprintReader.getInstance()
        
        if (fingerprintReaderCanSleep() && tryStandby) {
            self.fingerprintReader.standBy();
        } else {
            self.fingerprintReader.powerOff()
        }
    }

    @objc(scanFingerprint:) func scanFingerprint(command: CDVInvokedUrlCommand) {
        print("Scanning fingerprint")
        self.fingerprintCallbackId = command.callbackId;
        
        let imageTypeParam = command.arguments[0] as? String

        if (command.arguments.count > 1) {
            self.segmentedFingers = getArgumentAsBool(command: command, index: 1)
        }

        if (command.arguments.count > 2) {
            self.calculateNFIQScore = getArgumentAsBool(command: command, index: 2)
        }

        switch imageTypeParam {
        case "FLAT_SINGLE_FINGER":
            self.imageType = ImageType.FLAT_SINGLE_FINGER
            break
        case "FLAT_TWO_FINGERS":
            self.imageType = ImageType.FLAT_TWO_FINGERS
            break
        case "FLAT_FOUR_FINGERS":
            self.imageType = ImageType.FLAT_FOUR_FINGERS
            break
        case "ROLL_SINGLE_FINGER":
            self.imageType = ImageType.ROLL_SINGLE_FINGER
            break
        default:
            self.imageType = ImageType.FLAT_TWO_FINGERS
            break
        }

        self.fingerprintReader = iMatchFingerprintReader.getInstance()
        self.fingerprintReader.setDelegate(self)

        if self.fingerprintReader.getState() == FingerprintReaderState.ON {
            enroll()
        } else if (self.fingerprintReader.getState() == FingerprintReaderState.STAND_BY){
            self.fingerprintReader.wakeUp()
        } else {
            self.fingerprintReader.powerOn()
        }
    }

    @objc(scanFingerprintFAP20:) func scanFingerprintFAP20(command: CDVInvokedUrlCommand) {
        self.fingerprintCallbackId = command.callbackId;

        iMatchFingerprintReader.getInstance().setDelegate(self)
        iMatchFingerprintReader.getInstance().powerOn()
    }
    
    private func requestHardwareVersion() -> Hardware {
        let device = iMatchDevice.getInstance()
        
        let hardware = device.getHardwareVersion()
        guard hardware == .Unknown else { return hardware }
        
        let response = device.sendWithResponse(device: .Board, method: .INFO, param: "", timeOutInSeconds: 2.0)
        
        guard let response = response else {
            return .Unknown
        }
        
        device.processDeviceInfo(data: response.data)
        
        return device.getHardwareVersion()
    }

    @objc(hardwareVersion:) func hardwareVersion(command: CDVInvokedUrlCommand) {
        var hardware = iMatchDevice.getInstance().getHardwareVersion()
        
        if hardware == .Unknown {
            hardware = requestHardwareVersion()
        }
        
        var result = ""

        switch hardware {
        case
            Hardware.iMatch3,
            Hardware.iMatch3B:
            result = "iMatch20"
        case Hardware.iMatch45:
            result = "iMatch45"
        case Hardware.iMatch50:
            result = "iMatch50"
        default:
            result = "Unknown"
        }

        let message = createMessage(method: "hardwareversion", data: result)
        sendPluginResult(message: message, callback: command.callbackId);
    }

    @objc(readSmartcard:) func readSmartcard(command: CDVInvokedUrlCommand) {
        print("Reading smartcard")
        self.smartcardCallbackId = command.callbackId;

        self.smartcardReader = iMatchSmartcardReader.getInstance()
        self.smartcardReader.setDelegate(self)
        self.smartcardReader.powerOn()
    }

    @objc(powerOnSmartcard:) func powerOnSmartcard(command: CDVInvokedUrlCommand) {
        print("Powering on smartcard reader")
        self.smartcardCallbackId = command.callbackId;
        self.smartcardReader = iMatchSmartcardReader.getInstance()
        self.smartcardReader.setDelegate(self)
        self.smartcardReader.powerOn()
    }

    @objc(powerOffSmartcard:) func powerOffSmartcard(command: CDVInvokedUrlCommand) {
        print("Powering off fingerprint reader")
        self.smartcardCallbackId = command.callbackId;
        self.smartcardReader = iMatchSmartcardReader.getInstance()
        self.smartcardReader.powerOff()
    }
    
    func isFirmwareSupported() -> Bool {
        let hardware = self.imatchDevice.getHardwareVersion()
        var supported = (hardware != Hardware.Unknown)
        if (!supported ) {
            return false;
        }

        let minimalSupportedFirmware = "v1.12.2.5";
        if ((self.lastInfoMessage["version"]) != nil) {
            var connectedFirmwareVersion = (self.lastInfoMessage["version"] as! String);
            let parts = connectedFirmwareVersion.components(separatedBy: "-")
            if (parts.count > 0) {
                connectedFirmwareVersion = parts[0]
            }
            let compare = minimalSupportedFirmware.compare(connectedFirmwareVersion, options: .caseInsensitive)
            supported = (compare == .orderedAscending || compare == .orderedSame) ;
        }
        return supported
    }

    @objc(scanPassport:) func scanPassport(command: CDVInvokedUrlCommand) {
        print("Scanning passport")
        self.nfcCallbackId = command.callbackId;

        self.mrzkey = command.arguments[0] as! String
        
        if (!self.isFirmwareSupported()) {
            let device = Device(rawValue: "nfc") ?? .None
            let method = Method(rawValue: "mrtdread") ?? .NONE
            self.imatchDevice.send(device: device, method: method, param: self.mrzkey)
        } else {
        
            self.nfcReader = iMatchNFCReader.getInstance()
            self.nfcReader.setDelegate(self)
            self.nfcReader.powerOn()
        }
    }

    @objc(powerOnNFC:) func powerOnNFC(command: CDVInvokedUrlCommand) {
        print("Powering on NFC reader")
        self.nfcCallbackId = command.callbackId;
        self.nfcReader = iMatchNFCReader.getInstance()
        self.nfcReader.setDelegate(self)
        self.nfcReader.powerOn()
    }

    @objc(requestStatus:) func requestStatus(command: CDVInvokedUrlCommand) {
        print("requestStatus")
        self.imatchDevice.requestStatus();
        self.requestStatusCallbackId = command.callbackId;
    }

    @objc(requestDeviceInfo:) func requestDeviceInfo(command: CDVInvokedUrlCommand) {
        print("requestDeviceInfo")
        self.imatchDevice.requestDeviceInfo();
        self.requestDeviceInfoCallbackId = command.callbackId;
    }

    @objc(powerOffNFC:) func powerOffNFC(command: CDVInvokedUrlCommand) {
        print("Powering off NFC reader")
        self.nfcCallbackId = command.callbackId;
        self.nfcReader = iMatchNFCReader.getInstance()
        self.nfcReader.powerOff()
    }

    @objc(getEFCOMItems:) public func getEFCOMItems(command: CDVInvokedUrlCommand) {
        guard let efcom = self.efcom else { return }
        let items = efcom.getItems();

        if (items == nil) {
            let message = createMessage(method: "getEFCOMItems", data: "no efcomitems")
            sendPluginResult(message: message, callback: command.callbackId, ok: false, keep: false);
            return
        }

        var content = [String]()

        for item in items! {
            let itemName = item.toString()
            content.append(itemName);
        }

        let message = createMessage(method: "getEFCOMItems", data: content)
        sendPluginResult(message: message, callback: command.callbackId, keep: false);
    }
    
    @objc(validateComputedHashes:) func validateComputedHashes(command: CDVInvokedUrlCommand) {
        do {
            let validated = try self.nfcReader.validateComputedHashes()
            let message = createMessage(method: "computedHashes", data: ["validated": validated])
            sendPluginResult(message: message, callback: command.callbackId)
        } catch let error as NSError {
            print("Failed to validate hashes: \(error.localizedDescription)")
        }
    }

    func onInitSuccess() {
        print("onInitSuccess")
    }

    func onReceiveError(code: Int, message: String) {
        print("onReceiveError \(code) : " + message)
    }

    func onError(code: Int, message: String) {
        print("onError \(code) : " + message)
        let resultMessage = createMessage(method: "error", data: ["code" : code, "message" : message])
        sendPluginResult(message: resultMessage, callback: self.callbackId);
    }

    func dataAsJson(data: String) -> Any {
        do {
            let json = try JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as! [String: Any]
            return json;
        } catch _ as NSError {
            // nothing
        }

        return data;
    }

    func createMessage(method: String, data: Any? = nil) -> [String:Any] {
        var message : [String:Any] = [
            "method" : method
        ]

        if (data != nil) {
            message["data"] = data;
            if (data is String) {
                message["data"] = dataAsJson(data: data as! String);
            }
        }

        return message;
    }

    func sendPluginResult(message : [String:Any], callback: String, ok: Bool = true, keep: Bool = true) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message)

        if (!ok) {
            if let data = message["data"] as? String {
                pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: data);
            } else if let data = message["data"] as? [String:String] {
                pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: data["message"]);
            }
        }

        pluginResult?.setKeepCallbackAs(keep);
        self.commandDelegate!.send(pluginResult, callbackId: callback)
    }

    func onScanResult(results: [String]) {
        print("onScanResult")

        if (results.isEmpty){
            let resultMessage = createMessage(method: "list", data : ["message" : "No iMatch found, please try again" ])
            sendPluginResult(message: resultMessage, callback: self.listCallbackId, ok: false, keep: false);
        } else {
            print("Found the follow devices:")
            print(results)
            let resultMessage = createMessage(method: "list", data: results)
            sendPluginResult(message: resultMessage, callback: self.listCallbackId, keep: false);
        }
    }

    func onConnectionChange(connected: Bool) {
        print("onConnectionChange")
        let resultMessage = createMessage(method: "connectionchange", data: ["connected" : connected])
        sendPluginResult(message: resultMessage, callback: self.connectCallbackId);
        if (!connected) {
            sendPluginResult(message: resultMessage, callback: self.disconnectCallbackId);
            self.imatchDevice.removeDelegate(device: Device.Board, delegate: self)
        } else {
            self.imatchDevice.requestDeviceInfo()
            self.imatchDevice.requestStatus()
        }
    }

    // ImatchDeviceDelegate methods
    func didConnect() {
        print("didConnect")
        let resultMessage = createMessage(method: "connect", data: true)
        sendPluginResult(message: resultMessage, callback: self.callbackId);
        sendPluginResult(message: resultMessage, callback: self.connectCallbackId);
    }

    func didDisconnect() {
        print("didDisconnect")
        let resultMessage = createMessage(method: "disconnect", data: true)
        sendPluginResult(message: resultMessage, callback: self.callbackId, keep: false);
        sendPluginResult(message: resultMessage, callback: self.connectCallbackId, keep: false);
    }

    func onError(message: String) {
        print("onError: " + message)
        let resultMessage = createMessage(method: "error", data: message)

        sendPluginResult(message: resultMessage, callback: self.deviceCallbackId);
    }

    func onReceiveEvent(method: iMatchSDK.Method, data: String) {
        if (method == iMatchSDK.Method.DATETIME) {
            self.imatchDevice.requestDeviceInfo()
            self.imatchDevice.requestStatus()
        }

        let resultMessage = createMessage(method: method.rawValue, data: data)

        if (method == iMatchSDK.Method.STATUS) {
            let status = StatusMessage(data)
            self.lastChargingState = status.chargeState.isCharging()

            sendPluginResult(message: resultMessage, callback: self.requestStatusCallbackId, keep: false);
            self.requestStatusCallbackId = "";
        }

        if (method == iMatchSDK.Method.INFO) {
            self.lastInfoMessage = resultMessage["data"] as! [String : Any]
            sendPluginResult(message: resultMessage, callback: self.requestDeviceInfoCallbackId, keep: false);
            self.requestDeviceInfoCallbackId = "";
        }

        if ([iMatchSDK.Method.READ_BAC, iMatchSDK.Method.READ_DG1, iMatchSDK.Method.READ_DG2].contains(method)) {
            if (!self.isFirmwareSupported()) {
                let resultMessageOld = createMessage(method: method.rawValue, data: ["raw" : data, "fallback" : true])
                sendPluginResult(message: resultMessageOld, callback: self.nfcCallbackId);
                return;
            }
        }
        
        sendPluginResult(message: resultMessage, callback: self.deviceCallbackId);
    }

    func onFingerprintEvent(method: iMatchSDK.Method, data: String) {
        let hardware = imatchDevice.getHardwareVersion()
        
        if (hardware == Hardware.iMatch45 || hardware == Hardware.iMatch50) {
            handleIMatch45(method: method, data: data)
        } else {
            handleIMatch20(method: method, data: data)
        }
    }

    private func handleIMatch45(method: iMatchSDK.Method, data: String) {
        print("onFingerprintEvent \(method.rawValue) : " + data)
        var resultMessage = createMessage(method: method.rawValue, data: data)

        switch method {
            case .POWERON, .WAKE_UP:
                enroll()
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break
            case .ERROR:
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId, ok: false);
                break
            case .FP_QUALITY :
                let decodedData = Data(base64Encoded: data)!
                let decodedString = String(data: decodedData, encoding: .utf8)!
                resultMessage["data"] = decodedString.unicodeScalars.map { $0.value };

                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break;
            case .FP_COUNT :
                let decodedData = Data(base64Encoded: data)!
                let decodedString = String(data: decodedData, encoding: .utf8)!
                resultMessage["data"] = decodedString
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break;
            case .FP_NFIQ :
                resultMessage["data"] = Int(data);
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break;
            case .FP_FINISHED :
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break;
            default:
                sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
                break
        }
    }

    private func handleIMatch20(method: iMatchSDK.Method, data: String) {
        print("onFingerprintEvent")

        var resultMessage = createMessage(method: method.rawValue, data: data)

        switch method {
        case .POWERON, .WAKE_UP:
            let fpr = iMatchFingerprintReader.getInstance()
            fpr.loadData(jsonString: data)
            fpr.FAP20Enroll()
            sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
        case .NOTIFY:
            let ilv: ILVMessage = ILVMessage(raw: data)

            if (ilv.getInstruction() == ILVCommand.ILV_ENROLL){
                if let image = ilv.getFingerprintImage1() {
                    resultMessage["method"] = iMatchSDK.Method.FP_IMAGE.rawValue
                    resultMessage["data"] = [
                        "image" :image.getData().base64EncodedString(),
                        "image_height" :image.getImageHeight(),
                        "image_width" :image.getImageWidth(),
                        "image_dpi_vertical" :image.getDpiVertical(),
                        "image_dpi_horizontal" :image.getDpiHorizontal()
                    ]
                }
            } else if (ilv.getInstruction() == ILVCommand.ILV_ASYNC_MESSAGE) {
            
                if let ilvDataSlice = ilv.getData() {
                    let ilvData = Array(ilvDataSlice)

                    resultMessage["method"] = "message"

                    let position = ILVFinger(rawValue: ilvData[4])!
                    switch position {
                    case ILVFinger.NO_FINGER:
                        resultMessage["data"] = "No finger"
                        break
                    case ILVFinger.MOVE_UP:
                        resultMessage["data"] = "Move finger up"
                        break
                    case ILVFinger.MOVE_DOWN:
                        resultMessage["data"] = "Move finger down"
                        break
                    case ILVFinger.MOVE_LEFT:
                        resultMessage["data"] = "Move finger left"
                        break
                    case ILVFinger.MOVE_RIGHT:
                        resultMessage["data"] = "Move finger right"
                        break
                    case ILVFinger.PRESS_HARDER:
                        resultMessage["data"] = "Press harder"
                        break
                    case ILVFinger.REMOVE_FINGER:
                        resultMessage["data"] = "Remove finger"
                        break
                    case ILVFinger.FINGER_OK:
                        resultMessage["data"] = "Fingerprint OK"
                        break
                    case ILVFinger.FINGER_DETECTED:
                        resultMessage["data"] = "Finger detected"
                        break
                    default:
                        break
                    }
                }
            }
            sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId);
        default:
            break
        }
    }

    func onFingerprintError(code: Int, message: String) {
        if code == 999 { return }
        
        let resultMessage = createMessage(method: "error", data: ["code" : code, "message" : dataAsJson(data: message )])
        sendPluginResult(message: resultMessage, callback: self.fingerprintCallbackId, ok: false);
    }

    private func enroll() {
        let hardware = iMatchDevice.getInstance().getHardwareVersion()
        guard hardware == Hardware.iMatch45 || hardware == Hardware.iMatch50 else {
            print("Unsupported iMatch version for this type of fingerprint scanning")
            return
        }
        
        let params = FingerprintImageParameterBuilder()
        params.wsq()

        iMatchFingerprintReader.getInstance().enroll(
            imageType: self.imageType,
            calculateNfiqScore: self.calculateNFIQScore,
            timeout: 0,
            segmentFingerprints: self.segmentedFingers,
            imageParamBuilder: params,
            checkFingerGeometry: false,
            expectedFingers: 0x00
        )
    }

    func onSmartcardEvent(method: iMatchSDK.Method, data: String) {
        print("onSmartcardEvent")
        let resultMessage = createMessage(method: method.rawValue, data: data);

        switch method {
            case .ERROR:
                sendPluginResult(message: resultMessage, callback: self.smartcardCallbackId, ok: false);
                break
            default:
                sendPluginResult(message: resultMessage, callback: self.smartcardCallbackId);
                break
        }
    }

    func onSmartcardError(code: Int, message: String) {
        print("onSmartcardError \(code) : " + message)
        let resultMessage = createMessage(method: "error", data: ["code" : code, "message" : message])
        sendPluginResult(message: resultMessage, callback: self.smartcardCallbackId, ok: false);
    }

    func onNFCEvent(method: iMatchSDK.Method, data: String) {
        print("nfcevent " + method.rawValue)
        print(data)

        let NFCEventHandlers: [iMatchSDK.Method : (String) -> ()] = [
            iMatchSDK.Method.ERROR : self.processNFCError,
            iMatchSDK.Method.SHARE_SECURE_CHANNEL : self.processShareSecureChannel,
            iMatchSDK.Method.MRTD_INIT : self.processBAC,
            iMatchSDK.Method.POWERON : self.processNFCPowerOn,
            iMatchSDK.Method.READ_BAC : self.processReadBAC,
            iMatchSDK.Method.READ_EFCOM : self.processReadEFCOM,
            iMatchSDK.Method.READ_SOD : self.processReadSOD,
            iMatchSDK.Method.READ_DG1 : self.processReadDG1,
            iMatchSDK.Method.READ_DG2 : self.processReadDG2,
            iMatchSDK.Method.READ_DG5 : self.processReadDG5,
            iMatchSDK.Method.READ_DG7 : self.processReadDG7,
            iMatchSDK.Method.READ_DG11 : self.processReadDG11,
            iMatchSDK.Method.READ_DG12 : self.processReadDG12,
            iMatchSDK.Method.READ_DG13 : self.processReadDG13,
            iMatchSDK.Method.READ_DG14 : self.processReadDG14,
            iMatchSDK.Method.READ_DG15 : self.processReadDG15,
            iMatchSDK.Method.READ_DG16 : self.processReadDG16,
            iMatchSDK.Method.PERFORM_AA : self.processAA,
            iMatchSDK.Method.PERFORM_CA : self.processCA
        ]

        let handler = NFCEventHandlers[method]

        if let handler = handler {
            handler(data)
        }
    }

    func onNFCError(code: Int, message: String) {
        if code == 999 { return } // iMatch disconnect is already handeld by iMatchDelegate
        
        let resultMessage = createMessage(method: "error", data: ["code" : code, "message" : dataAsJson(data: message)])
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId, ok: false);
    }

    private func processNFCPowerOn(_ data: String) {
        let nfcReader = iMatchNFCReader.getInstance()
        
        debugPrint(self.mrzkey)

        nfcReader.startHybridPACE(mrz: self.mrzkey)
    }

    private func processNFCError(_ data: String) {
        let resultMessage = createMessage(method: "error", data: data)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId, ok: false);
    }

    private func processShareSecureChannel(_ data: String) {
        let messagingProtocol = data;

        if (!messagingProtocol.isEmpty) {
            self.accessControl = messagingProtocol

            let resultMessage = createMessage(method: "access_control", data: [
                "type" : "PACE",
                "protocol" : messagingProtocol
            ])

            sendPluginResult(message: resultMessage, callback: self.nfcCallbackId, keep: true)
            self.requestData()
        } else {
            print("Unable to start the secure context, continue with BAC")
            iMatchNFCReader.getInstance().startBAC(self.mrzkey)
        }
    }

    private func processBAC(_ data: String) {
        if (data == "BAC failed") {
            let resultMessage = createMessage(method: iMatchSDK.Method.READ_BAC.rawValue, data: data)
            sendPluginResult(message: resultMessage, callback: self.nfcCallbackId)
        } else {
            self.accessControl = "BAC"
            let resultMessage = createMessage(method: "access_control", data: ["type" : "BAC"])
            sendPluginResult(message: resultMessage, callback: self.nfcCallbackId)
            self.requestData()
        }
    }

    private func requestData() {
        let nfcReader = iMatchNFCReader.getInstance()
        
        self.dg1 = nil
        self.dg14 = nil
        self.dg15 = nil

        nfcReader.readDataGroups(datagroups: [
            MRTDtag.DG1,
            MRTDtag.SOD,
            MRTDtag.EFCOM,
        ])
    }

    private func processReadBAC(_ data: String) {
        var resultMessage = createMessage(method: "access_control", data: ["type" : "BAC"])
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId)
        resultMessage = createMessage(method: iMatchSDK.Method.READ_BAC.rawValue, data: data)
        sendPluginResult(message: resultMessage, callback:  self.nfcCallbackId);
    }

    private func processReadSOD(_ data: String) {
        self.sod = nil
        self.sod = Sod(input: Data(base64Encoded: data)!)
        guard let sod = sod else { return }

        var result: [String:Any] = [
            "raw": data,
            "signed_data": sod.getSignedData() ?? "",
            "sod_verification": sod.verify(IssuingState: dg1!.getCountry()!) ?? false
        ];

        let cert: X509Wrapper = sod.getCertificate()!

        cert.getItemsAsDict().forEach { (key: CertificateItem, value: String) in
            let name = key.rawValue.replacingOccurrences(of: " ",  with: "_", options: .literal, range: nil)
            result[name.lowercased()] = value
        }

        result["certificate"] = cert.certToPEM();

        let resultMessage = createMessage(method: iMatchSDK.Method.READ_SOD.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId)
    }
            
    private func canReadCA() -> Bool {
        guard let allowedDatagroups = self.allowedDatagroups else { return false }
         
        return allowedDatagroups.contains(.DG14)
    }
    
    private func canReadAA() -> Bool {
        guard let allowedDatagroups = self.allowedDatagroups else { return false }
         
        return allowedDatagroups.contains(.DG15)
    }
    
    private func startAA() {
        nfcReader.performAA()
    }
    
    private func requestDataGroups() {
        var datagroups: [MRTDtag] = allowedDatagroups ?? []
        
        let hasRequestedDG14 = self.dg14 != nil
        let hasRequestedDG15 = self.dg15 != nil
        
        datagroups = datagroups.filter {
            let removeDG14 = $0 == .DG14 && hasRequestedDG14
            let removeDG15 = $0 == .DG15 && hasRequestedDG15
            
            return !(removeDG14 || removeDG15)
        }
        
        self.nfcReader.readDataGroups(datagroups: datagroups)
    }

    private func processReadEFCOM(_ data: String) {
        let efcom = EFCom(input: Data(base64Encoded: data)!)
        self.efcom = efcom

        var result : [String:Any] = [
            "raw" : data
        ]

        if let items = efcom.getItems() {
            items.forEach { tag in
                result[tag.toString()] = tag.rawValue
            }

            let datagroups = items.filter {
                return !($0 == MRTDtag.EFCOM || $0 == MRTDtag.SOD)
            }
            
            let allowedDatagroups = datagroups.filter {
                return !($0 == MRTDtag.DG3 || $0 == MRTDtag.DG4)
            }

            var groups : [String] = [];

            allowedDatagroups.forEach { tag in
                groups.append(tag.toString())
            }

            result["groups"] = groups;
            
            self.allowedDatagroups = allowedDatagroups
        }

        performProtocols(ca: true, aa: true)

        let resultMessage = createMessage(method: iMatchSDK.Method.READ_EFCOM.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    

    private func processCA(_ data: String) {

        let ca = CAResult(input: data)

        let result: [String : Any] = [
            "raw": data,
            "validated": ca.succeeded,
            "protocol": ca.protocolName ?? "",
            "parameter": ca.parameter ?? "",
            "cipher": ca.cipher ?? ""
        ]
            
        let resultMessage = createMessage(method: iMatchSDK.Method.PERFORM_CA.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
        
        performProtocols(ca: false, aa: !ca.succeeded)
    }

    private func processReadDG1(_ data: String) {
        let dg1 = EFDataGroup1(input: Data(base64Encoded: data)!)
        self.dg1 = dg1

        let formatter = createDateFormatter()
        formatter.dateFormat = "dd-MM-YYYY"

        let dob = dg1.getDateOfBirth()
        let expiry = dg1.getExpiryDate()
        var hash = ""
        if (self.sod != nil) {
            hash = dg1.hash(sod!) ?? ""
        }
        
        let validated = (sod?.validateHash(dg1) ?? false) && self.nfcReader.validateComputedHash(dg: "DG1")

        let result: [String:Any] = [
            "raw": data,
            "mrz": dg1.getMRZ() ?? "",
            "name": dg1.getName() ?? "",
            "surname": dg1.getSurname() ?? "",
            "gender": dg1.getGender()?.toString() ?? "",
            "date_of_birth": dob != nil ? formatter.string(from: dob!) : "",
            "personal_number": dg1.getPersonalNumber() ?? "",
            "country": dg1.getCountry() ?? "",
            "nationality": dg1.getNationality() ?? "",
            "document_type": dg1.getDocumentType()?.toString() ?? "",
            "document_number": dg1.getDocumentNumber() ?? "",
            "expiry_date": expiry != nil ? formatter.string(from: expiry!) : "",
            "validated": validated,
            "hash": hash,
        ]

        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG1.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId)
    }

    private func processReadDG2(_ data: String) {
        let sod = self.sod
        let dg2 = EFDataGroup2(input: Data(base64Encoded: data)!)
        
        let image = dg2.getImage()
        var hash = ""
        if (sod != nil) {
            hash = dg2.hash(sod!) ?? ""
        }
        
        let validated = (sod?.validateHash(dg2) ?? false) && self.nfcReader.validateComputedHash(dg: "DG2")
        
        let result: [String:Any] = [
            "raw": data,
            "image_type": image?.type.rawValue ?? "",
            "image": image?.toJpeg()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": hash,
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG2.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }

    private func processReadDG5(_ data: String) {
        let sod = self.sod!
        let dg5 = EFDataGroup5(input: Data(base64Encoded: data)!)
        
        let validated = sod.validateHash(dg5) && self.nfcReader.validateComputedHash(dg: "DG5")
        
        let result: [String:Any] = [
            "raw": data,
            "image": dg5.getPortrait()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": dg5.hash(sod) ?? "",
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG5.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }

    private func processReadDG7(_ data: String) {
        let sod = self.sod!
        let dg7 = EFDataGroup7(input: Data(base64Encoded: data)!)
        
        let validated = sod.validateHash(dg7) && self.nfcReader.validateComputedHash(dg: "DG7")
        
        let result: [String:Any] = [
            "raw": data,
            "image": dg7.getSignature()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": dg7.hash(sod) ?? "",
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG7.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }

    private func processReadDG11(_ data: String) {
        let sod = self.sod!
        let dg11 = EFDataGroup11(input: Data(base64Encoded: data)!)
        
        let formatter = createDateFormatter()
        formatter.dateFormat = "dd-MM-YYYY"
        
        let validated = sod.validateHash(dg11) && self.nfcReader.validateComputedHash(dg: "DG11")
            
        var result: [String:Any] = [
            "raw": data,
            "validated": validated,
            "hash": dg11.hash(sod) ?? "",
            
            "tag_list": dg11.getTagList()?.base64EncodedString() ?? "",
            "custody_information": dg11.getCustodyInformation() ?? "",
            "full_name": dg11.getFullNameOfDocumentHolder() ?? "",
            "other_tds": dg11.getOtherTDs() ?? "",
            "permanent_address": dg11.getPermanentAddress() ?? "",
            "personal_summary": dg11.getPersonalSummary() ?? "",
            "personal_number": dg11.getPersonalNumber() ?? "",
            "place_of_birth": dg11.getPlaceOfBirth() ?? "",
            "profession": dg11.getProfession() ?? "",
            "proof_of_citizenship": dg11.getProofOfCitizenship()?.base64EncodedString() ?? "",
            "telephone": dg11.getTelephone() ?? "",
            "title": dg11.getTitle() ?? ""
        ]
        
        if let dob = dg11.getDateOfBirth() {
            result["date_of_birth"] = formatter.string(from: dob)
        }
    
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG11.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processReadDG12(_ data: String) {
        let sod = self.sod!
        let dg12 = EFDataGroup12(input: Data(base64Encoded: data)!)
        
        let formatter = createDateFormatter()
        formatter.dateFormat = "dd-MM-YYYY"
        
        let validated = sod.validateHash(dg12) && self.nfcReader.validateComputedHash(dg: "DG12")
        
        var result: [String:Any] = [
            "raw": data,
            "validated": validated,
            "hash": dg12.hash(sod) ?? "",
            
            "tag_list": dg12.getTagList()?.base64EncodedString() ?? "",
            "endorsements": dg12.getEndorsements() ?? "",
            "front_of_document": dg12.getFrontOfDocument()?.base64EncodedString() ?? "",
            "rear_of_document": dg12.getRearOfDocument()?.base64EncodedString() ?? "",
            "issuing_authority": dg12.getIssuingAuthority() ?? "",
            "serial_number_of_personalization_system": dg12.getSerialNumberOfPersonalizationSystem() ?? "",
            "tax_exit_requirements": dg12.getTaxExitRequirements() ?? ""
        ]
       
        if let dateOfIssue = dg12.getDateOfIssue() {
            result["date_of_issue"] = formatter.string(from: dateOfIssue)
        }
        
        if let dateOfDocumentPersonalization = dg12.getDateTimeOfDocumentPersonalization() {
            result["date_of_document_personalization"] = formatter.string(from: dateOfDocumentPersonalization)
        }
    
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG12.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processReadDG13(_ data: String) {
        let sod = self.sod!
        let dg13 = EFDataGroup13(input: Data(base64Encoded: data)!)
        let validated = sod.validateHash(dg13) && self.nfcReader.validateComputedHash(dg: "DG13")
        
        let result: [String:Any] = [
            "raw": data,
            "security_infos": dg13.getOptionalDetails()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": dg13.hash(sod) ?? "",
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG13.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processReadDG14(_ data: String) {
        let sod = self.sod!
        let dg14 = EFDataGroup14(input: Data(base64Encoded: data)!)
        self.dg14 = dg14
        let validated = sod.validateHash(dg14) && self.nfcReader.validateComputedHash(dg: "DG14")
        
        let result: [String:Any] = [
            "raw": data,
            "security_infos": dg14.getSecurityInfo()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": dg14.hash(sod) ?? "",
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG14.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processReadDG15(_ data: String) {
        let sod = self.sod!
        let dg15 = EFDataGroup15(input: Data(base64Encoded: data)!)
        self.dg15 = dg15
        let validated = sod.validateHash(dg15) && self.nfcReader.validateComputedHash(dg: "DG15")
        
        let result: [String:Any] = [
            "raw": data,
            "active_authenticaton_public_key_info": dg15.getActiveAuthenticationPublicKeyInfo()?.base64EncodedString() ?? "",
            "validated": validated,
            "hash": dg15.hash(sod) ?? "",
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG15.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processReadDG16(_ data: String) {
        let sod = self.sod!
        let dg16 = EFDataGroup16(input: Data(base64Encoded: data)!)
        
        let formatter = createDateFormatter()
        formatter.dateFormat = "dd-MM-YYYY"
        
        let validated = sod.validateHash(dg16) && self.nfcReader.validateComputedHash(dg: "DG16")
        
        var result: [String:Any] = [
            "raw": data,
            "validated": validated,
            "hash": dg16.hash(sod) ?? "",
        ]
        
        if let personToNotify = dg16.getPersonToNotify() {
            result["name_of_person"] = personToNotify.nameOfPerson ?? ""
            result["address"] = personToNotify.address ?? ""
            result["phone"] = personToNotify.phone ?? ""
            
            if let dateDataRecorded = personToNotify.dateDataRecorded {
                result["date_data_recorded"] = formatter.string(from: dateDataRecorded)
            }
        }
        
        let resultMessage = createMessage(method: iMatchSDK.Method.READ_DG16.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
    }
    
    private func processAA(_ data: String) {
        let aaResult = AAResult(data: data)
        
        let result: [String : Any] = [
            "raw": data,
            "validated": aaResult.succeeded
        ]
        
        let resultMessage = createMessage(method: iMatchSDK.Method.PERFORM_AA.rawValue, data: result)
        sendPluginResult(message: resultMessage, callback: self.nfcCallbackId);
        
        performProtocols(ca: false, aa: false)
    }
    
    private func performProtocols(ca: Bool, aa: Bool) {
        if ca && canReadCA() {
            self.nfcReader.verifyPresenceCA { is_present in
                if is_present {
                    self.nfcReader.performCA()
                } else {
                    self.performProtocols(ca: false, aa: true)
                }
            }
            
            return
        }
        
        if aa && canReadAA() {
            self.startAA()
            return
        }
        
        requestDataGroups()
    }
    
}

fileprivate func createDateFormatter() -> DateFormatter {
    let dateFormatter = DateFormatter()
    
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.calendar = Calendar(identifier: .iso8601)
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "yyyymmdd"
    
    return dateFormatter
}
