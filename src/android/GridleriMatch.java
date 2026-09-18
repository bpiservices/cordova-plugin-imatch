package com.gridler.imatch;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Base64;
import android.util.Log;

import com.gridler.imatchlib.Device;
import com.gridler.imatchlib.FingerType;
import com.gridler.imatchlib.FingerprintReaderState;
import com.gridler.imatchlib.FirmwareUpdateResponse;
import com.gridler.imatchlib.FirmwareUpdateTaskWrapper;
import com.gridler.imatchlib.HardwareVersion;
import com.gridler.imatchlib.ImageType;
import com.gridler.imatchlib.ImatchFingerPrintListener;
import com.gridler.imatchlib.ImatchListener;
import com.gridler.imatchlib.ImatchManagerListener;
import com.gridler.imatchlib.ImatchNFCListener;
import com.gridler.imatchlib.ImatchSmartCardListener;
import com.gridler.imatchlib.Method;
import com.gridler.imatchlib.SecondStageUpdateTaskWrapper;
import com.gridler.imatchsdk.GaugeModel;
import com.gridler.imatchsdk.GaugeUtils;
import com.gridler.imatchsdk.ILVAsyncMessage;
import com.gridler.imatchsdk.ILVConstant;
import com.gridler.imatchlib.ImatchDevice;
import com.gridler.imatchsdk.ImatchFPEnrollmentParams;
import com.gridler.imatchsdk.ImatchFPEnrollmentResult;
import com.gridler.imatchsdk.ImatchFPImageParameterBuilder;
import com.gridler.imatchsdk.ImatchFingerprintReader;
import com.gridler.imatchsdk.ImatchManager;
import com.gridler.imatchsdk.ImatchNFCReader;
import com.gridler.imatchsdk.ImatchSmartcardReader;
import com.gridler.imatchsdk.FingerprintImage;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Cordova bridge over the iMatch Android SDK.
 */
public class GridleriMatch extends CordovaPlugin implements ImatchManagerListener, ImatchListener,
        ImatchFingerPrintListener, ImatchSmartCardListener, ImatchNFCListener {

    private static final String TAG = "GridleriMatch";
    private static final int PERMISSION_REQUEST = 55433;
    private static final int SCAN_TIMEOUT_MS = 2000;
    private static final int INFO_TIMEOUT_MS = 2000;

    private static final Map<Method, String> METHOD_NAMES = new HashMap<>();
    static {
        METHOD_NAMES.put(Method.POWERON, "power_on");
        METHOD_NAMES.put(Method.POWERONRAW, "power_on_raw");
        METHOD_NAMES.put(Method.POWEROFF, "power_off");
        METHOD_NAMES.put(Method.MRTD_INIT, "mrtdinit");
        METHOD_NAMES.put(Method.MRTD_READ, "mrtdread");
        METHOD_NAMES.put(Method.NEXT_FILE, "mp1_next_file");
        METHOD_NAMES.put(Method.RESEND_FILE, "mp1_resend_file");
        METHOD_NAMES.put(Method.CHECK_FILES_TO_UPDATE, "mp1_check_files_to_update");
        METHOD_NAMES.put(Method.REMOVE, "mp1_remove");
    }

    private static final EnumSet<Method> BOARD_ONLY = EnumSet.of(
            Method.INFO, Method.STATUS, Method.DATETIME, Method.RESET, Method.ECHO, Method.LED,
            Method.BUTTON, Method.REBOOT, Method.WARNING, Method.RESTART, Method.TEST,
            Method.FLASH, Method.FLASH_LOADED, Method.BOOTLOADER_LOADED, Method.FIRMWARE_UPDATE, Method.MP1_DFU);

    private static final Map<Integer, String> FAP20_INSTRUCTIONS = new HashMap<>();
    static {
        FAP20_INSTRUCTIONS.put(0x00, "No finger");
        FAP20_INSTRUCTIONS.put(0x01, "Move finger up");
        FAP20_INSTRUCTIONS.put(0x02, "Move finger down");
        FAP20_INSTRUCTIONS.put(0x03, "Move finger left");
        FAP20_INSTRUCTIONS.put(0x04, "Move finger right");
        FAP20_INSTRUCTIONS.put(0x05, "Press harder");
        FAP20_INSTRUCTIONS.put(0x06, "Latent");
        FAP20_INSTRUCTIONS.put(0x07, "Remove finger");
        FAP20_INSTRUCTIONS.put(0x08, "Fingerprint OK");
        FAP20_INSTRUCTIONS.put(0x09, "Finger detected");
        FAP20_INSTRUCTIONS.put(0x10, "Finger misplaced");
        FAP20_INSTRUCTIONS.put(0x11, "Live OK");
    }

    private static final Map<Integer, String> EFCOM_TAGS = new HashMap<>();
    static {
        int[] tags = {0x61, 0x75, 0x63, 0x76, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70};
        for (int i = 0; i < tags.length; i++) {
            EFCOM_TAGS.put(tags[i], "DG" + (i + 1));
        }
    }

    private ImatchManager manager;
    private ImatchDevice device;
    private ImatchFingerprintReader fingerprintReader;
    private ImatchSmartcardReader smartcardReader;
    private ImatchNFCReader nfcReader;

    private CallbackContext listCallback;
    private CallbackContext connectCallback;
    private CallbackContext disconnectCallback;
    private CallbackContext disconnectHandler;
    private CallbackContext eventListener;
    private CallbackContext fingerprintCallback;
    private CallbackContext smartcardCallback;
    private CallbackContext nfcCallback;
    private CallbackContext statusCallback;
    private CallbackContext infoCallback;
    private CallbackContext updateCallback;

    private boolean initialized;
    private boolean disconnectRequested;
    private boolean lastCharging;
    private boolean isUpdating;
    private int updateMax;
    private int lastUpdatePercent = -1;

    private ImageType imageType = ImageType.FLAT_TWO_FINGERS;
    private boolean segmentedFingers;
    private boolean calculateNfiq;
    private boolean enrollPending;
    private boolean fap20Pending;

    private byte[] lastEfcom;

    // ---------------------------------------------------------------- Cordova entry point

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callback) throws JSONException {
        Log.d(TAG, "execute: " + action);
        switch (action) {
            case "initialize": initialize(callback); return true;
            case "list": list(callback); return true;
            case "connect": connect(args.optString(0, ""), callback); return true;
            case "disconnect": disconnect(callback); return true;
            case "connected": connected(callback); return true;
            case "setDisconnectHandler": disconnectHandler = callback; keepAlive(callback); return true;
            case "setReceiveEventListener": eventListener = callback; keepAlive(callback); return true;
            case "hardwareVersion": hardwareVersion(callback); return true;
            case "requestDeviceInfo": infoCallback = callback; requireDevice().RequestDeviceInfo(); return true;
            case "requestStatus": statusCallback = callback; requireDevice().RequestStatus(); return true;
            case "isCharging": send(callback, message("ischarging", new JSONObject().put("charging", lastCharging)), true, false); return true;
            case "write": write(args.opt(0), callback); return true;
            case "needsUpdate": needsUpdate(callback); return true;
            case "update": update(callback); return true;
            case "cancelUpdate": cancelUpdate(callback); return true;
            case "powerOnFingerprint": powerOnFingerprint(callback); return true;
            case "powerOffFingerprint": powerOffFingerprint(args.optBoolean(0, false), callback); return true;
            case "scanFingerprint": scanFingerprint(args.optString(0, ""), args.optBoolean(1, false), args.optBoolean(2, false), callback); return true;
            case "scanFingerprintFAP20": scanFingerprintFAP20(callback); return true;
            case "powerOnSmartcard": smartcardCallback = callback; requireSmartcard().powerReaderOn(""); keepAlive(callback); return true;
            case "powerOffSmartcard": requireSmartcard().powerReaderOff(); send(callback, message("poweroff smartcard", null), true, false); return true;
            case "readSmartcard": smartcardCallback = callback; requireSmartcard().powerReaderOn("readKnownATRs"); keepAlive(callback); return true;
            case "powerOnNFC": nfcCallback = callback; requireNfc().powerReaderOn(""); keepAlive(callback); return true;
            case "powerOffNFC": requireNfc().powerReaderOff(); send(callback, message("poweroff nfc", null), true, false); return true;
            case "scanPassport": scanPassport(args.optString(0, ""), callback); return true;
            case "getEFCOMItems": getEFCOMItems(callback); return true;
            case "validateComputedHashes":
                send(callback, message("computedHashes", new JSONObject()
                        .put("validated", false)
                        .put("message", "Passive authentication is not available in the Android plugin yet")), false, false);
                return true;
            default:
                return false;
        }
    }

    @Override
    public void onDestroy() {
        if (device != null && device.Connected()) {
            device.Disconnect();
        }
        super.onDestroy();
    }

    // ---------------------------------------------------------------- lifecycle

    private void initialize(CallbackContext callback) throws JSONException {
        ensureInitialized();
        send(callback, message("initialize", null), true, false);
    }

    private void ensureInitialized() {
        if (initialized) {
            return;
        }
        manager = ImatchManager.getInstance();
        device = ImatchDevice.getInstance();
        device.AddListener(Device.Board, this);
        fingerprintReader = ImatchFingerprintReader.getInstance();
        fingerprintReader.setListener(this);
        smartcardReader = ImatchSmartcardReader.getInstance();
        smartcardReader.setListener(this);
        nfcReader = ImatchNFCReader.getInstance();
        nfcReader.setListener(this);
        manager.Init(cordova.getActivity().getApplication(), true, this);
        initialized = true;
    }

    private ImatchDevice requireDevice() {
        ensureInitialized();
        return device;
    }

    private ImatchSmartcardReader requireSmartcard() {
        ensureInitialized();
        return smartcardReader;
    }

    private ImatchNFCReader requireNfc() {
        ensureInitialized();
        return nfcReader;
    }

    private void list(CallbackContext callback) {
        ensureInitialized();
        listCallback = callback;
        String[] permissions = requiredPermissions();
        if (!hasAllPermissions(permissions)) {
            cordova.requestPermissions(this, PERMISSION_REQUEST, permissions);
            return;
        }
        manager.Scan(SCAN_TIMEOUT_MS);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST) {
            return;
        }
        boolean granted = grantResults.length > 0;
        for (int result : grantResults) {
            granted &= result == PackageManager.PERMISSION_GRANTED;
        }
        if (!granted) {
            sendError(listCallback, "list", "Bluetooth permission denied");
            return;
        }
        manager.Scan(SCAN_TIMEOUT_MS);
    }

    @Override
    public void onScanResult(Map<String, String> scanResult) {
        try {
            List<String> names = new ArrayList<>(scanResult.keySet());
            Collections.sort(names);
            if (names.isEmpty()) {
                send(listCallback, message("list", new JSONObject().put("message", "No iMatch found, please try again")), false, false);
            } else {
                send(listCallback, message("list", new JSONArray(names)), true, false);
            }
        } catch (JSONException e) {
            sendError(listCallback, "list", e.getMessage());
        }
    }

    private void connect(String name, CallbackContext callback) throws JSONException {
        ensureInitialized();
        connectCallback = callback;
        disconnectRequested = false;
        if (name.isEmpty()) {
            send(callback, message("connect", new JSONObject().put("connected", false).put("message", "No device name given")), false, false);
            return;
        }
        if (manager.ScanResult == null || manager.ScanResult.isEmpty()) {
            send(callback, message("connect", new JSONObject().put("connected", false).put("message", "Call list before connect")), false, false);
            return;
        }
        boolean started = device.Connect(name);
        if (started) {
            send(callback, message("connect", new JSONObject().put("connected", true)), true, true);
        } else {
            send(callback, message("connect", new JSONObject().put("connected", false).put("message", "Connection failed")), false, false);
        }
    }

    private void disconnect(CallbackContext callback) throws JSONException {
        ensureInitialized();
        disconnectCallback = callback;
        if (device.Connected()) {
            disconnectRequested = true;
            device.Disconnect();
        } else {
            send(callback, message("disconnect", true), true, false);
        }
    }

    private void connected(CallbackContext callback) throws JSONException {
        boolean isConnected = device != null && device.Connected();
        send(callback, message("connected", new JSONObject().put("connected", isConnected)), isConnected, false);
    }

    @Override
    public void onConnectionChange(Boolean connected) {
        try {
            JSONObject payload = message("connectionchange", new JSONObject().put("connected", connected));
            send(connectCallback, payload, true, true);
            if (connected) {
                device.RequestDeviceInfo();
                device.RequestStatus();
            } else {
                send(disconnectHandler, payload, true, true);
                if (disconnectRequested) {
                    disconnectRequested = false;
                    send(disconnectCallback, message("disconnect", true), true, false);
                    disconnectCallback = null;
                }
                enrollPending = false;
                fap20Pending = false;
            }
        } catch (JSONException e) {
            Log.e(TAG, "onConnectionChange: " + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- board events

    @Override
    public void onReceiveEvent(Method method, String data) {
        String name = methodName(method);
        JSONObject payload = message(name, dataAsJson(data));
        if (method == Method.STATUS) {
            GaugeModel gauge = GaugeUtils.parseGaugeInfo(data);
            if (gauge != null) {
                lastCharging = gauge.cs || "charging".equalsIgnoreCase(gauge.state);
            }
            if (statusCallback != null) {
                send(statusCallback, payload, true, false);
                statusCallback = null;
            }
        }
        if (method == Method.INFO && infoCallback != null) {
            send(infoCallback, payload, true, false);
            infoCallback = null;
        }
        send(eventListener, payload, true, true);
    }

    @Override
    public void onReceiveError(int code, String message) {
        send(eventListener, errorMessage(code, message), false, true);
    }

    @Override
    public void onInitSuccess() {
        Log.i(TAG, "iMatch SDK initialised");
    }

    @Override
    public void onError(int code, String message) {
        Log.e(TAG, "onError " + code + ": " + message);
        if (code == 201 && connectCallback != null) {
            send(connectCallback, errorMessage(code, message), false, true);
            return;
        }
        if (listCallback != null && code == 901) {
            send(listCallback, errorMessage(code, message), false, false);
            return;
        }
        send(eventListener, errorMessage(code, message), false, true);
    }

    // ---------------------------------------------------------------- device

    private void hardwareVersion(final CallbackContext callback) {
        ensureInitialized();
        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                HardwareVersion hardware = device.GetHardwareVersion();
                if (hardware == null && device.Connected()) {
                    try {
                        device.SendWithResponse(Device.Board, Method.INFO, "", INFO_TIMEOUT_MS);
                    } catch (Exception e) {
                        Log.w(TAG, "hardwareVersion: info request failed: " + e.getMessage());
                    }
                    hardware = device.GetHardwareVersion();
                }
                send(callback, message("hardwareversion", hardwareName(hardware)), true, false);
            }
        });
    }

    private static String hardwareName(HardwareVersion hardware) {
        if (hardware == null) {
            return "Unknown";
        }
        switch (hardware) {
            case IMATCH_20_3:
            case IMATCH_20_3B:
                return "iMatch20";
            case IMATCH_45:
                return "iMatch45";
            case IMATCH_50:
                return "iMatch50";
            case IMATCH_60:
                return "iMatch60";
            default:
                return "Unknown";
        }
    }

    private boolean fingerprintReaderCanSleep() {
        HardwareVersion hardware = device.GetHardwareVersion();
        return hardware == HardwareVersion.IMATCH_45 || hardware == HardwareVersion.IMATCH_50 || hardware == HardwareVersion.IMATCH_60;
    }

    private void write(Object raw, CallbackContext callback) {
        ensureInitialized();
        try {
            JSONObject json = raw instanceof JSONObject ? (JSONObject) raw : new JSONObject(String.valueOf(raw));
            Device target = deviceFromName(json.getString("device"));
            Method method = methodFromName(json.getString("method"));
            String params = json.optString("params", "");
            if (target == null || method == null) {
                send(callback, message("write", new JSONObject().put("code", 400).put("message", "Unknown device or method")), false, false);
                return;
            }
            device.Send(target, method, params);
            send(callback, message("write", null), true, false);
        } catch (JSONException e) {
            try {
                send(callback, message("write", new JSONObject().put("code", 400).put("message", e.getMessage())), false, false);
            } catch (JSONException ignored) {
                callback.error(e.getMessage());
            }
        }
    }

    // ---------------------------------------------------------------- firmware

    private void needsUpdate(CallbackContext callback) throws JSONException {
        ensureInitialized();
        String installed = device.GetFirmwareVersion();
        String available = device.GetSdkFirmwareVersion(cordova.getContext());
        boolean required = false;
        if (installed != null && !installed.isEmpty()) {
            try {
                required = ImatchDevice.compareVersions(installed, available) < 0;
            } catch (Exception e) {
                Log.w(TAG, "needsUpdate: cannot compare " + installed + " with " + available);
            }
        }
        send(callback, message("needsupdate", new JSONObject()
                .put("required", required)
                .put("version", available)
                .put("installed", installed)), true, false);
    }

    private void update(final CallbackContext callback) throws JSONException {
        ensureInitialized();
        if (isUpdating) {
            send(callback, message("update", new JSONObject().put("error", "update in progress")), false, false);
            return;
        }
        isUpdating = true;
        updateCallback = callback;
        lastUpdatePercent = -1;
        updateMax = device.GetSdkFirmwareSize(cordova.getContext());
        final boolean secondStage = fingerprintReaderCanSleep();

        final FirmwareUpdateResponse secondStageResponse = new FirmwareUpdateResponse() {
            @Override public void updateProgress(int progress, String file) { reportUpdateProgress(progress, file, false); }
            @Override public void updateCompleted() { finishUpdate(); }
            @Override public void updateFailed(Exception e) { failUpdate(e); }
            @Override public void restart(int restartTicks) { updateMax = restartTicks; }
        };
        final FirmwareUpdateResponse firmwareResponse = new FirmwareUpdateResponse() {
            @Override public void updateProgress(int progress, String file) { reportUpdateProgress(progress, file, false); }
            @Override public void updateCompleted() {
                if (!secondStage) {
                    finishUpdate();
                    return;
                }
                updateMax = 100;
                cordova.getActivity().runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        SecondStageUpdateTaskWrapper.getInstance().initializeSecondStageUpdate(cordova.getActivity(), secondStageResponse, false);
                    }
                });
            }
            @Override public void updateFailed(Exception e) { failUpdate(e); }
            @Override public void restart(int restartTicks) { updateMax = restartTicks; }
        };

        cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                FirmwareUpdateTaskWrapper.getInstance().initializeFirmwareUpdate(cordova.getActivity(), firmwareResponse, false);
            }
        });
    }

    private void reportUpdateProgress(int progress, String action, boolean completed) {
        int percent = updateMax > 0 ? Math.min(100, (int) ((long) progress * 100 / updateMax)) : 0;
        if (percent == lastUpdatePercent && !completed) {
            return;
        }
        lastUpdatePercent = percent;
        try {
            send(updateCallback, message("update", new JSONObject()
                    .put("progress", percent)
                    .put("action", action)
                    .put("completed", completed)), true, !completed);
        } catch (JSONException e) {
            Log.e(TAG, "reportUpdateProgress: " + e.getMessage());
        }
    }

    private void finishUpdate() {
        isUpdating = false;
        updateMax = 100;
        reportUpdateProgress(100, "Update completed", true);
        updateCallback = null;
    }

    private void failUpdate(Exception e) {
        isUpdating = false;
        try {
            send(updateCallback, message("update", new JSONObject().put("error", e == null ? "unknown" : String.valueOf(e.getMessage()))), false, false);
        } catch (JSONException ignored) {
            // nothing more to report
        }
        updateCallback = null;
    }

    private void cancelUpdate(CallbackContext callback) {
        FirmwareUpdateTaskWrapper.getInstance().cancelUpdate();
        SecondStageUpdateTaskWrapper.getInstance().cancelUpdate();
        isUpdating = false;
        send(callback, message("cancel_update", null), true, false);
    }

    // ---------------------------------------------------------------- fingerprint

    private void powerOnFingerprint(CallbackContext callback) {
        ensureInitialized();
        fingerprintCallback = callback;
        enrollPending = false;
        fap20Pending = false;
        FingerprintReaderState state = fingerprintReader.getState();
        if (fingerprintReaderCanSleep() && state == FingerprintReaderState.STAND_BY) {
            fingerprintReader.wakeUp();
        } else if (state != FingerprintReaderState.ON) {
            fingerprintReader.powerOn();
        }
        send(callback, message("poweron finger", null), true, true);
    }

    private void powerOffFingerprint(boolean tryStandby, CallbackContext callback) {
        ensureInitialized();
        enrollPending = false;
        fap20Pending = false;
        if (fingerprintReaderCanSleep() && tryStandby) {
            fingerprintReader.sleep();
        } else {
            fingerprintReader.powerOff();
        }
        send(callback, message("poweroff finger", null), true, false);
    }

    private void scanFingerprint(String imageTypeName, boolean segmented, boolean nfiq, CallbackContext callback) {
        ensureInitialized();
        fingerprintCallback = callback;
        segmentedFingers = segmented;
        calculateNfiq = nfiq;
        switch (imageTypeName) {
            case "FLAT_SINGLE_FINGER": imageType = ImageType.FLAT_SINGLE_FINGER; break;
            case "FLAT_FOUR_FINGERS": imageType = ImageType.FLAT_FOUR_FINGERS; break;
            case "ROLL_SINGLE_FINGER": imageType = ImageType.ROLL_SINGLE_FINGER; break;
            default: imageType = ImageType.FLAT_TWO_FINGERS; break;
        }
        fap20Pending = false;
        FingerprintReaderState state = fingerprintReader.getState();
        if (state == FingerprintReaderState.ON) {
            enrollPending = false;
            enroll();
        } else if (state == FingerprintReaderState.STAND_BY) {
            enrollPending = true;
            fingerprintReader.wakeUp();
        } else {
            enrollPending = true;
            fingerprintReader.powerOn();
        }
    }

    private void enroll() {
        ImatchFPImageParameterBuilder params = new ImatchFPImageParameterBuilder().wsq();
        fingerprintReader.enroll(imageType, calculateNfiq, 0, segmentedFingers, params, false, FingerType.NONE);
    }

    private void scanFingerprintFAP20(CallbackContext callback) {
        ensureInitialized();
        fingerprintCallback = callback;
        enrollPending = false;
        fap20Pending = true;
        if (fingerprintReader.getState() == FingerprintReaderState.ON) {
            enrollFap20();
        } else {
            fingerprintReader.powerOn();
        }
    }

    private void enrollFap20() {
        ImatchFPEnrollmentParams params = new ImatchFPEnrollmentParams();
        params.configAsynchronousEvent(ImatchFPEnrollmentParams.ASYNC_MSG_FINGER_POSITION | ImatchFPEnrollmentParams.ASYNC_MSG_ENROLLMENT_STEP);
        params.setConsolidation((byte) 1);
        params.setExportTemplate(false);
        params.setExportImage(ILVConstant.ID_COMPRESSION_WSQ, (byte) 15);
        fingerprintReader.enroll(params);
    }

    @Override
    public void onFingerprintEvent(Method method, String data) {
        if (BOARD_ONLY.contains(method)) {
            return;
        }
        try {
            if (fap20Pending || (device.GetHardwareVersion() != null && !fingerprintReaderCanSleep())) {
                handleFap20Event(method, data);
            } else {
                handleIbEvent(method, data);
            }
        } catch (Exception e) {
            Log.e(TAG, "onFingerprintEvent: " + e.getMessage());
            send(fingerprintCallback, errorMessage(500, e.getMessage()), false, true);
        }
    }

    private void handleIbEvent(Method method, String data) throws JSONException {
        JSONObject payload = message(methodName(method), dataAsJson(data));
        switch (method) {
            case POWERON:
            case WAKE_UP:
                if (enrollPending) {
                    enrollPending = false;
                    enroll();
                }
                send(fingerprintCallback, payload, true, true);
                break;
            case ERROR:
                send(fingerprintCallback, payload, false, true);
                break;
            case FP_QUALITY: {
                byte[] decoded = Base64.decode(data, Base64.NO_WRAP);
                JSONArray qualities = new JSONArray();
                for (byte b : decoded) {
                    qualities.put(b & 0xFF);
                }
                payload.put("data", qualities);
                send(fingerprintCallback, payload, true, true);
                break;
            }
            case FP_COUNT:
                payload.put("data", new String(Base64.decode(data, Base64.NO_WRAP)));
                send(fingerprintCallback, payload, true, true);
                break;
            case FP_NFIQ:
                try {
                    payload.put("data", Integer.parseInt(data.trim()));
                } catch (NumberFormatException ignored) {
                    // keep the raw string
                }
                send(fingerprintCallback, payload, true, true);
                break;
            default:
                send(fingerprintCallback, payload, true, true);
                break;
        }
    }

    private void handleFap20Event(Method method, String data) throws Exception {
        JSONObject payload = message(methodName(method), dataAsJson(data));
        switch (method) {
            case POWERON:
            case WAKE_UP:
                if (fap20Pending) {
                    enrollFap20();
                }
                send(fingerprintCallback, payload, true, true);
                break;
            case NOTIFY: {
                byte[] bytes = Base64.decode(data, Base64.NO_WRAP);
                if (bytes.length == 0) {
                    return;
                }
                if (bytes[0] == ILVConstant.ILV_ENROLL) {
                    ImatchFPEnrollmentResult result = new ImatchFPEnrollmentResult(bytes);
                    FingerprintImage image = result.getFingerprintImage();
                    if (image != null) {
                        payload.put("method", "fp_image");
                        payload.put("data", new JSONObject()
                                .put("image", Base64.encodeToString(image.getImageData(), Base64.NO_WRAP))
                                .put("header", bytesToHex(image.getImageHeader()))
                                .put("status", result.getEnrollmentResult()));
                    } else {
                        payload.put("method", "fp_enroll_result");
                        payload.put("data", new JSONObject().put("status", result.getEnrollmentResult()));
                    }
                    fap20Pending = false;
                } else if (bytes[0] == ILVConstant.ILV_ASYNC_MESSAGE) {
                    ILVAsyncMessage async = new ILVAsyncMessage(bytes);
                    if (async.getCommandType() == ILVAsyncMessage.MORPHO_CALLBACK_COMMAND_CMD && async.getCommandCmd() != null) {
                        int instruction = async.getCommandCmd().getInstruction();
                        String text = FAP20_INSTRUCTIONS.get(instruction);
                        payload.put("method", "message");
                        payload.put("data", text != null ? text : "Instruction " + instruction);
                    } else {
                        return;
                    }
                }
                send(fingerprintCallback, payload, true, true);
                break;
            }
            case ERROR:
                send(fingerprintCallback, payload, false, true);
                break;
            default:
                send(fingerprintCallback, payload, true, true);
                break;
        }
    }

    @Override
    public void onFingerprintError(int code, String message) {
        if (code == 999) {
            return;
        }
        send(fingerprintCallback, errorMessage(code, message), false, true);
    }

    // ---------------------------------------------------------------- smartcard

    @Override
    public void onSmartCardEvent(Method method, String data) {
        if (BOARD_ONLY.contains(method)) {
            return;
        }
        JSONObject payload = message(methodName(method), dataAsJson(data));
        send(smartcardCallback, payload, method != Method.ERROR, true);
    }

    @Override
    public void onSmartCardError(int code, String message) {
        if (code == 999) {
            return;
        }
        send(smartcardCallback, errorMessage(code, message), false, true);
    }

    // ---------------------------------------------------------------- nfc

    private void scanPassport(String mrz, CallbackContext callback) throws JSONException {
        ensureInitialized();
        nfcCallback = callback;
        lastEfcom = null;
        String key = mrz.replaceAll("\\s+", "");
        if (key.isEmpty()) {
            send(callback, message("error", new JSONObject().put("code", 400).put("message", "MRZ is required")), false, false);
            return;
        }
        // mrz, bypassPace, checkMac, includeHeaders, chipAuthentication
        device.Send(Device.NfcReader, Method.MRTD_READ, key + ",0,1,1,0");
        keepAlive(callback);
    }

    private void getEFCOMItems(CallbackContext callback) {
        if (lastEfcom == null) {
            send(callback, message("getEFCOMItems", "no efcomitems"), false, false);
            return;
        }
        send(callback, message("getEFCOMItems", efcomItems(lastEfcom)), true, false);
    }

    @Override
    public void onNFCEvent(Method method, String data) {
        if (BOARD_ONLY.contains(method)) {
            return;
        }
        try {
            JSONObject payload = message(methodName(method), dataAsJson(data));
            switch (method) {
                case READ_BAC:
                case READ_EAC: {
                    JSONObject result = new JSONObject()
                            .put("type", method == Method.READ_BAC ? "BAC" : "PACE")
                            .put("raw", dataAsJson(data));
                    Object parsed = dataAsJson(data);
                    boolean success = "1".equals(data.trim())
                            || (parsed instanceof JSONObject && ((JSONObject) parsed).optInt("eacResult", 0) == 1);
                    result.put("success", success);
                    send(nfcCallback, message("access_control", result), success, true);
                    break;
                }
                case READ_EFCOM: {
                    lastEfcom = Base64.decode(data, Base64.NO_WRAP);
                    payload.put("data", new JSONObject().put("raw", data).put("items", efcomItems(lastEfcom)));
                    send(nfcCallback, payload, true, true);
                    break;
                }
                case READ_SOD:
                    payload.put("data", new JSONObject().put("raw", data));
                    send(nfcCallback, payload, true, true);
                    break;
                case READ_DG1: {
                    byte[] dg1 = Base64.decode(data, Base64.NO_WRAP);
                    payload.put("data", new JSONObject().put("raw", data).put("mrz", extractMrz(dg1)));
                    send(nfcCallback, payload, true, true);
                    break;
                }
                case READ_DG2: {
                    byte[] dg2 = Base64.decode(data, Base64.NO_WRAP);
                    JSONObject result = new JSONObject().put("raw", data);
                    int[] photo = locatePhoto(dg2);
                    if (photo != null) {
                        byte[] photoBytes = Arrays.copyOfRange(dg2, photo[0], dg2.length);
                        result.put("image", Base64.encodeToString(photoBytes, Base64.NO_WRAP));
                        result.put("mimeType", PHOTO_MIME_TYPES[photo[1]]);
                    }
                    payload.put("data", result);
                    send(nfcCallback, payload, true, true);
                    break;
                }
                case READ_ERROR:
                case ERROR:
                    send(nfcCallback, payload, false, true);
                    break;
                default:
                    send(nfcCallback, payload, true, true);
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "onNFCEvent: " + e.getMessage());
            send(nfcCallback, errorMessage(500, e.getMessage()), false, true);
        }
    }

    @Override
    public void onNFCError(int code, String message) {
        if (code == 999) {
            return;
        }
        send(nfcCallback, errorMessage(code, message), false, true);
    }

    private static final byte[][] PHOTO_SIGNATURES = {
            {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF},
            {0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, (byte) 0x87, 0x0A},
            {(byte) 0xFF, 0x4F, (byte) 0xFF, 0x51},
            {(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A},
    };
    private static final String[] PHOTO_MIME_TYPES = {"image/jpeg", "image/jp2", "image/jp2", "image/png"};

    private static int[] locatePhoto(byte[] dg2) {
        int bestIndex = -1;
        int bestSignature = -1;
        for (int s = 0; s < PHOTO_SIGNATURES.length; s++) {
            int index = indexOf(dg2, PHOTO_SIGNATURES[s]);
            if (index >= 0 && (bestIndex < 0 || index < bestIndex)) {
                bestIndex = index;
                bestSignature = s;
            }
        }
        return bestIndex < 0 ? null : new int[]{bestIndex, bestSignature};
    }

    private static String extractMrz(byte[] dg1) {
        int index = indexOf(dg1, new byte[]{0x5F, 0x1F});
        if (index < 0 || index + 2 >= dg1.length) {
            return new String(dg1).replaceAll("[^A-Z0-9<]", "");
        }
        int pos = index + 2;
        int length = dg1[pos] & 0xFF;
        pos++;
        if (length == 0x81 && pos < dg1.length) {
            length = dg1[pos] & 0xFF;
            pos++;
        } else if (length == 0x82 && pos + 1 < dg1.length) {
            length = ((dg1[pos] & 0xFF) << 8) | (dg1[pos + 1] & 0xFF);
            pos += 2;
        }
        int end = Math.min(dg1.length, pos + length);
        return new String(Arrays.copyOfRange(dg1, pos, end));
    }

    private static JSONArray efcomItems(byte[] efcom) {
        JSONArray items = new JSONArray();
        int index = indexOf(efcom, new byte[]{0x5C});
        if (index < 0 || index + 1 >= efcom.length) {
            return items;
        }
        int length = efcom[index + 1] & 0xFF;
        for (int i = index + 2; i < Math.min(efcom.length, index + 2 + length); i++) {
            String name = EFCOM_TAGS.get(efcom[i] & 0xFF);
            items.put(name != null ? name : String.format("0x%02X", efcom[i] & 0xFF));
        }
        return items;
    }

    // ---------------------------------------------------------------- helpers

    private String[] requiredPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT};
        }
        return new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION};
    }

    private boolean hasAllPermissions(String[] permissions) {
        for (String permission : permissions) {
            if (!cordova.hasPermission(permission)) {
                return false;
            }
        }
        return true;
    }

    private static String methodName(Method method) {
        String name = METHOD_NAMES.get(method);
        return name != null ? name : method.name().toLowerCase();
    }

    private static Method methodFromName(String name) {
        for (Method method : Method.values()) {
            if (methodName(method).equals(name)) {
                return method;
            }
        }
        return null;
    }

    private static Device deviceFromName(String name) {
        switch (name) {
            case "sys": return Device.Board;
            case "fpr": return Device.FingerprintReader;
            case "scr": return Device.SmartcardReader;
            case "nfc": return Device.NfcReader;
            default: return null;
        }
    }

    private static Object dataAsJson(String data) {
        if (data == null) {
            return JSONObject.NULL;
        }
        String trimmed = data.trim();
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            try {
                Object value = new JSONTokener(trimmed).nextValue();
                if (value instanceof JSONObject || value instanceof JSONArray) {
                    return value;
                }
            } catch (JSONException ignored) {
                // fall through to the raw string
            }
        }
        return data;
    }

    private static JSONObject message(String method, Object data) {
        JSONObject json = new JSONObject();
        try {
            json.put("method", method);
            if (data != null) {
                json.put("data", data);
            }
        } catch (JSONException e) {
            Log.e(TAG, "message: " + e.getMessage());
        }
        return json;
    }

    private static JSONObject errorMessage(int code, String text) {
        try {
            return message("error", new JSONObject().put("code", code).put("message", dataAsJson(text)));
        } catch (JSONException e) {
            return message("error", text);
        }
    }

    private static void send(CallbackContext callback, JSONObject payload, boolean ok, boolean keep) {
        if (callback == null) {
            return;
        }
        PluginResult result = new PluginResult(ok ? PluginResult.Status.OK : PluginResult.Status.ERROR, payload);
        result.setKeepCallback(keep);
        callback.sendPluginResult(result);
    }

    private static void sendError(CallbackContext callback, String method, String text) {
        send(callback, message(method, text), false, false);
    }

    private static void keepAlive(CallbackContext callback) {
        PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
        result.setKeepCallback(true);
        callback.sendPluginResult(result);
    }

    private static int indexOf(byte[] haystack, byte[] needle) {
        outer:
        for (int i = 0; i <= haystack.length - needle.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return i;
        }
        return -1;
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02X", b & 0xFF));
        }
        return sb.toString();
    }
}
