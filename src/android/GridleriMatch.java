package com.gridler.imatch;
import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothGatt;
import android.util.Base64;
import android.util.Log;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONObject;

import com.clj.fastble.BleManager;
import com.clj.fastble.callback.BleGattCallback;
import com.clj.fastble.callback.BleMtuChangedCallback;
import com.clj.fastble.callback.BleNotifyCallback;
import com.clj.fastble.callback.BleScanCallback;
import com.clj.fastble.callback.BleWriteCallback;
import com.clj.fastble.data.BleDevice;
import com.clj.fastble.exception.BleException;
import com.clj.fastble.scan.BleScanRuleConfig;

import java.io.UnsupportedEncodingException;
import java.util.List;
import java.util.UUID;

public class GridleriMatch extends CordovaPlugin {
    private final static String TAG = GridleriMatch.class.getSimpleName();
    CallbackContext listCallbackContext;
    CallbackContext connectCallbackContext;
    CallbackContext subscribeCallbackContext;

    public List<BleDevice> ScanResult = null;
    private BleDevice ImatchBleDevice = null;
    private byte [] mPackage = new byte[262144];
    private int mPackageLen = 0;

    private static final int REQUEST_CODE_ENABLE_PERMISSION = 55433;

    public static String IMATCH_SPS_SERVICE           = "0783b03e-8535-b5a0-7140-a304d2495cb7";
    public static String IMATCH_READ_CHARACTERISTIC   = "0783b03e-8535-b5a0-7140-a304d2495cb8";
    public static String IMATCH_WRITE_CHARACTERISTIC  = "0783b03e-8535-b5a0-7140-a304d2495cba";

    @Override
    public boolean execute(String action, JSONArray args,
                           final CallbackContext callbackContext) {
        Log.i(TAG, "execute: " + action);

        if ("list".equals(action)) {
            listCallbackContext = callbackContext;
            Scan();
            return true;
        }

        if ("isEnabled".equals(action)) {
            if (isBluetoothEnabled()) {
                callbackContext.success();
                return true;
            }
            else {
                callbackContext.error("Bluetooth is not enabled");
                return false;
            }
        }

        if ("isConnected".equals(action)) {
            if (BleManager.getInstance().isConnected(ImatchBleDevice)) {
                callbackContext.success();
                return true;
            }
            else {
                callbackContext.error("iMatch is not connected");
                return false;
            }
        }

        if ("connect".equals(action)) {
            connectCallbackContext = callbackContext;

            String device = "";
            try {
                device = args.getString(0);
            } catch (Exception ex) {
            }

            Connect(device);
            return true;
        }

        if ("disconnect".equals(action)) {
            callbackContext.success();
            return true;
        }

        if ("subscribe".equals(action)) {
            subscribeCallbackContext = callbackContext;
            return true;
        }

        if ("unsubscribe".equals(action)) {
            subscribeCallbackContext = null;
            return true;
        }

        if ("write".equals(action)) {
            String data = "";
            try {
                data = args.getString(0);
            } catch (Exception ex) {
            }

            transmit(data);
        }

        callbackContext.error("Unknown command: " + action);
        return true;
    }

    private boolean isBluetoothEnabled() {
        BluetoothAdapter mBluetoothAdapter = BluetoothAdapter.getDefaultAdapter();

        if (mBluetoothAdapter == null) {
            Log.e(TAG, "Device does not support Bluetooth");
            return false;
        }

        if (!mBluetoothAdapter.isEnabled()) {
            Log.e(TAG, "Bluetooth is not enabled");
            return false;
        }

        Log.d(TAG, "Bluetooth is enabled");
        return true;
    }

    private void Scan() {
        checkPermissions();

        UUID[] serviceUuids = new UUID[]{UUID.fromString(IMATCH_SPS_SERVICE)};

        BleManager.getInstance().init(cordova.getActivity().getApplication());

        BleScanRuleConfig scanRuleConfig = new BleScanRuleConfig.Builder()
                .setServiceUuids(serviceUuids)
                .setAutoConnect(false)
                .setScanTimeOut(2000)
                .build();

        BleManager.getInstance().initScanRule(scanRuleConfig);

        BleManager.getInstance().scan(new BleScanCallback() {
            @Override
            public void onScanStarted(boolean success) {
                Log.d(TAG, "onScanStarted result " + success);
                if (!success)
                {
                    listCallbackContext.error("BLE not enabled");
                }
            }

            @Override
            public void onScanning(BleDevice bleDevice) {
                Log.d(TAG, "onScanning found device: " + bleDevice.getName() + " mac: " + bleDevice.getMac() + " rssi: " + bleDevice.getRssi());
            }

            @Override
            public void onScanFinished(List<BleDevice> scanResultList) {
                Log.d(TAG, "onScanFinished. Found " + scanResultList.size() + " devices");
                ScanResult = scanResultList;

                JSONArray devices = new JSONArray();
                for(BleDevice ble : ScanResult) {
                    JSONObject device = new JSONObject();
                    try {
                        Log.d(TAG, "found: " +  ble.getName() + " - " + ble.getMac());
                        device.put("name", ble.getName());
                        device.put("uuid", ble.getMac());
                        device.put("id", ble.getMac());
                        device.put("rssi", ble.getRssi());
                        devices.put(device);
                    } catch (Exception ex) {
                    }
                }

                listCallbackContext.success(devices);
            }
        });
    }

    private boolean Connect(String imatchName) {
        if (imatchName.length() < 1) {
            return false;
        }

        for(BleDevice bleDevice : ScanResult) {
            String name = bleDevice.getName();
            if (name != null && !name.contains("-") && bleDevice.getMac() != null && bleDevice.getMac().length() > 0) {
                String devId = bleDevice.getMac().replace(":", "");
                if (devId.length() == 12) {
                    name += "-" + devId.substring(8);
                }
            }

            if (imatchName.length() < 1) {
                ImatchBleDevice = bleDevice;
                break;
            }

            if (imatchName.equals(bleDevice.getMac())) {
                ImatchBleDevice = bleDevice;
                break;
            }

        }
        if (ImatchBleDevice == null) {
            Log.e(TAG, "Connect called but device does not exist in scanresults");
            connectCallbackContext.error("Connect called but device does not exist in scanresults");
            return false;
        }

        BleManager.getInstance().connect(ImatchBleDevice, new BleGattCallback() {
            @Override
            public void onStartConnect() {
                Log.d(TAG, "onStartConnect");
            }

            @Override
            public void onConnectFail(BleDevice bleDevice, BleException exception) {
                Log.d(TAG, "onConnectFail");
                connectCallbackContext.error(exception.getDescription());
            }

            @Override
            public void onConnectSuccess(BleDevice bleDevice, BluetoothGatt gatt, int status) {
                BleManager.getInstance().setMtu(
                    bleDevice,
                    256,
                    new BleMtuChangedCallback() {
                        @Override
                        public void onSetMTUFailure(BleException exception) {
                            Log.e(TAG, "onSetMTUFailure: " + exception.getDescription());
                        }

                        @Override
                        public void onMtuChanged(int mtu) {
                            Log.v(TAG, "onMtuChanged. value: " + mtu);
                            BleManager.getInstance().setSplitWriteNum(mtu);
                            BleManager.getInstance().notify(
                                ImatchBleDevice,
                                IMATCH_SPS_SERVICE,
                                IMATCH_READ_CHARACTERISTIC,
                                new BleNotifyCallback() {
                                    @Override
                                    public void onNotifySuccess() {
                                        Log.d(TAG, "onConnectSuccess");
                                        connectCallbackContext.success();
                                    }

                                    @Override
                                    public void onNotifyFailure(BleException exception) {
                                        Log.e(TAG, "onNotifyFailure: " + exception.getDescription());
                                    }

                                    @Override
                                    public void onCharacteristicChanged(byte[] data) {
                                        Log.v(TAG, "onCharacteristicChanged. " + data.length + " bytes");
                                        receiveRaw(data);
                                    }
                                }
                            );
                        }
                    }
                );
            }

            @Override
            public void onDisConnected(boolean isActiveDisConnected, BleDevice bleDevice, BluetoothGatt gatt, int status) {
                Log.d(TAG, "onDisConnected");
            }
        });

        return true;
    }

    private byte[] createRawPackage(String json_package)  {
        byte [] payload = json_package.getBytes();
        int payload_len = payload.length;
        byte[] packet = new byte[payload.length+7];

        packet[0] = 0x01; // SOH
        packet[1] = (byte)(payload_len& 0xFF);   // LOW
        packet[2] = (byte)(payload_len>>8);     // HIGH
        packet[3] = 0x02; // STX

        System.arraycopy(payload, 0, packet, 4, payload.length);

        int LRC = 0;
        for (byte aPayload : payload) LRC += aPayload;
        LRC = ((LRC&0xFF)^0xFF)+1;

        packet[packet.length-3] = 0x03; // ETX
        packet[packet.length-2] = (byte)LRC;
        packet[packet.length-1] = 0x04; // EOT

        return packet;
    }

    private void transmit(String data) {
        String json_package = "";

        try {
            json_package = new String(Base64.decode(data, Base64.NO_WRAP),"UTF-8");
        } catch (UnsupportedEncodingException e) {
            e.printStackTrace();
        }

        Log.i(TAG, "--> " + json_package);
        byte [] packet = createRawPackage(json_package);
        BleManager.getInstance().write(
            ImatchBleDevice,
            IMATCH_SPS_SERVICE,
            IMATCH_WRITE_CHARACTERISTIC,
            packet,
            new BleWriteCallback() {
                @Override
                public void onWriteSuccess(int current, int total, byte[] justWrite) {
                    Log.v(TAG, "onWriteSuccess: " + current + " of " + total + ". " + justWrite.length + " bytes.");
                }

                @Override
                public void onWriteFailure(BleException exception) {
                    Log.e(TAG, "onWriteFailure: " + exception.getDescription());
                }
            });
    }

    private void receiveRaw(byte[] raw_bytes) {
        if(raw_bytes.length==0)
            return;

        for (byte raw_byte : raw_bytes) {
            // Prevent restart of parsing because of 0x01 in header
            // (2nd byte length)
            if (raw_byte == 0x01 && mPackageLen > 4) {
                // prevent checksum causing invalid new start so
                // check for absence of ETX
                if (mPackage[mPackageLen - 1] != 0x03)
                    mPackageLen = 0;
            }

            // prevent overflow
            if (mPackageLen >= mPackage.length)
                return;

            mPackage[mPackageLen++] = raw_byte;
            // prevent early out because of 0x04 in header
            if (raw_byte == 0x04 && mPackageLen > 4) {
                // Double check to prevent early out because of 4 in
                // checksum. So check presence of ETX
                if (mPackage[mPackageLen - 3] != 0x03)
                    continue;

                int json_len = mPackageLen - 7;

                if (json_len >= 0) {
                    byte[] json_raw = new byte[json_len];
                    System.arraycopy(mPackage, 4, json_raw, 0, json_len);
                    String json = new String(json_raw);

                    json = json.replace("\"b'","");
                    json = json.replace("'\"","");

                    Log.i(TAG, "<-- " + json);
                    try {
                        PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, json);
                        pluginResult.setKeepCallback(true);
                        subscribeCallbackContext.sendPluginResult(pluginResult);
                    } catch (Exception e) {
                        Log.e(TAG, e.getLocalizedMessage());
                    }
                }
            }
        }
    }

    private boolean hasAllPermissions(String[] permissions) {
        for (String permission : permissions) {
            if(!cordova.hasPermission(permission)) {
                return false;
            }
        }
        return true;
    }

    private void checkPermissions()
    {
        String[] permissions = new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION};
        if (!hasAllPermissions(permissions))
        {
            cordova.requestPermissions(this, REQUEST_CODE_ENABLE_PERMISSION, permissions);
        }
    }

}