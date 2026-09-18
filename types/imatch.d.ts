// Type declarations for cordova-plugin-imatch 2.x (window.iMatch)

declare namespace IMatch {
    interface Message<T = any> {
        method: string;
        data?: T;
    }

    type SuccessCallback<T = any> = (message: Message<T>) => void;
    type ErrorCallback = (message: Message<any> | string) => void;

    type HardwareVersion = 'iMatch20' | 'iMatch45' | 'iMatch50' | 'Unknown';

    type FingerprintImageType =
        | 'FLAT_SINGLE_FINGER'
        | 'FLAT_TWO_FINGERS'
        | 'FLAT_FOUR_FINGERS'
        | 'ROLL_SINGLE_FINGER';

    type Device = 'sys' | 'fpr' | 'scr' | 'nfc';

    interface ConnectResult {
        connected: boolean;
        message?: string;
    }

    interface ConnectionChange {
        connected: boolean;
    }

    interface DeviceInfo {
        version: string;
        datetime?: string;
        fastflash?: boolean;
        hardware?: number;
    }

    interface DeviceStatus {
        state: 'good' | 'fair' | 'poor' | 'charging';
        cs?: number;
        cv?: number;
        cl?: number;
    }

    interface NeedsUpdateResult {
        required: boolean;
        version?: string;
    }

    interface UpdateProgress {
        progress: number;
        action: string;
        completed: boolean;
    }

    interface UpdateError {
        error: string;
    }

    interface FingerprintImage {
        image: string;
        image_height?: number;
        image_width?: number;
        [key: string]: any;
    }

    type DeviceEvent = Message<any>;

    interface Plugin {
        initialize(success?: SuccessCallback, error?: ErrorCallback): void;
        list(success: SuccessCallback<string[]>, error?: ErrorCallback): void;
        connect(deviceName: string, success: SuccessCallback<ConnectResult | ConnectionChange>, error?: ErrorCallback): void;
        disconnect(success?: SuccessCallback, error?: ErrorCallback): void;
        connected(success: SuccessCallback<ConnectionChange>, error?: ErrorCallback): void;
        setDisconnectHandler(handler: SuccessCallback<ConnectionChange>): void;
        setReceiveEventListener(listener: (event: DeviceEvent) => void, error?: ErrorCallback): void;

        hardwareVersion(success: SuccessCallback<HardwareVersion>, error?: ErrorCallback): void;
        requestDeviceInfo(success: SuccessCallback<DeviceInfo>, error?: ErrorCallback): void;
        requestStatus(success: SuccessCallback<DeviceStatus>, error?: ErrorCallback): void;
        isCharging(success: SuccessCallback<{ charging: boolean }>, error?: ErrorCallback): void;
        write(data: string | object, success?: SuccessCallback, error?: ErrorCallback): void;

        needsUpdate(success: SuccessCallback<NeedsUpdateResult>, error?: ErrorCallback): void;
        update(progress: SuccessCallback<UpdateProgress>, error?: ErrorCallback | SuccessCallback<UpdateError>): void;
        cancelUpdate(success?: SuccessCallback): void;

        powerOnFingerprint(success?: SuccessCallback, error?: ErrorCallback): void;
        powerOffFingerprint(tryStandby?: boolean, success?: SuccessCallback, error?: ErrorCallback): void;
        scanFingerprint(
            imageType: FingerprintImageType,
            segmented: boolean,
            calculateNFIQ: boolean,
            success: SuccessCallback<FingerprintImage | any>,
            error?: ErrorCallback
        ): void;
        scanFingerprintFAP20(success: SuccessCallback, error?: ErrorCallback): void;

        powerOnSmartcard(success?: SuccessCallback, error?: ErrorCallback): void;
        powerOffSmartcard(success?: SuccessCallback, error?: ErrorCallback): void;
        readSmartcard(success: SuccessCallback, error?: ErrorCallback): void;

        powerOnNFC(success?: SuccessCallback, error?: ErrorCallback): void;
        powerOffNFC(success?: SuccessCallback, error?: ErrorCallback): void;
        scanPassport(mrz: string, success: SuccessCallback, error?: ErrorCallback): void;
        getEFCOMItems(success: SuccessCallback<string[]>, error?: ErrorCallback): void;
        validateComputedHashes(success: SuccessCallback<{ validated: boolean }>, error?: ErrorCallback): void;
    }
}

interface Window {
    iMatch: IMatch.Plugin;
}

declare var iMatch: IMatch.Plugin;
