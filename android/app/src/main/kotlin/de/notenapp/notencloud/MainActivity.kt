package de.notenapp.notencloud

import android.content.Intent
import android.provider.Settings
import android.view.InputDevice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "de.notenapp.notencloud/pedal"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getConnectedInputDevices" -> {
                    try {
                        val devicesList = mutableListOf<Map<String, Any>>()
                        val deviceIds = InputDevice.getDeviceIds()
                        for (id in deviceIds) {
                            val device = InputDevice.getDevice(id) ?: continue
                            val isExternal = device.isExternal
                            val sources = device.sources
                            val isKeyboard = (sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD
                            val isGamepad = (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
                                            (sources and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
                            
                            // Include external keyboards, gamepads, pedals
                            if (isKeyboard || isGamepad || isExternal) {
                                devicesList.add(
                                    mapOf(
                                        "id" to device.id,
                                        "name" to device.name,
                                        "vendorId" to device.vendorId,
                                        "productId" to device.productId,
                                        "isExternal" to isExternal,
                                        "isKeyboard" to isKeyboard
                                    )
                                )
                            }
                        }
                        result.success(devicesList)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
