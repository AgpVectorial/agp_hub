
package com.agptech.agp_wear_hub

// Importuri SDK Green Orange - de adăugat după identificarea pachetului corect

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "agp_sdk"
    private val HR_EVENT_CHANNEL = "agp_sdk/hr_stream"

    private var hrSink: EventChannel.EventSink? = null
    private var hrTimer: java.util.Timer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel: scan / connect / readMetrics / startHR / stopHR
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                "scan" -> {
                    // Scanare reală cu SDK-ul Green Orange
                    // Exemplu: filtrează device-urile Green Orange după UUID sau MAC
                    val uuid = call.argument<String>("uuid")
                    val mac = call.argument<String>("mac")
                    val foundDevices = mutableListOf<Map<String, Any>>()
                    try {
                        BleScannerHelper.getInstance().scanDevice(this, uuid, object : ScanWrapperCallback {
                            override fun onScanResult(device: Device) {
                                // Filtrare device după UUID/MAC
                                if ((uuid != null && device.uuid == uuid) ||
                                    (mac != null && device.macAddress == mac)) {
                                    val deviceMap = mapOf(
                                        "id" to device.macAddress,
                                        "name" to device.name,
                                        "rssi" to device.rssi,
                                        "uuid" to device.uuid
                                    )
                                    foundDevices.add(deviceMap)
                                }
                            }
                        })
                        // Returnează lista filtrată (poate fi nevoie de callback async)
                        result.success(foundDevices)
                    } catch (e: Exception) {
                        result.error("SCAN_ERROR", e.message, null)
                    }
                }

                "connect" -> {
                    // Conectare reală cu SDK-ul Green Orange
                    val mac = call.argument<String>("id")
                    try {
                        BleOperateManager.getInstance().connectDirectly(mac)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CONNECT_ERROR", e.message, null)
                    }
                }

                "readMetrics" -> {
                    // Citește metrice reale din SDK-ul Green Orange
                    val mac = call.argument<String>("id")
                    val metrics = mutableMapOf<String, Any>()
                    try {
                        // Exemplu: citire puls
                        CommandHandle.getInstance().executeReqCmd(
                            HeartRateSettingReq.getReadInstance(),
                            object : ICommandResponse<HeartRateSettingRsp> {
                                override fun onDataResponse(resultEntity: HeartRateSettingRsp) {
                                    metrics["heartRate"] = resultEntity.heartInterval
                                }
                            }
                        )
                        // Exemplu: citire pași
                        CommandHandle.getInstance().executeReqCmd(
                            SimpleKeyReq(Constants.CMD_GET_STEP_TODAY),
                            object : ICommandResponse<TodaySportDataRsp> {
                                override fun onDataResponse(resultEntity: TodaySportDataRsp) {
                                    metrics["steps"] = resultEntity.totalSteps
                                }
                            }
                        )
                        // Exemplu: citire baterie
                        CommandHandle.getInstance().executeReqCmd(
                            SimpleKeyReq(Constants.CMD_GET_DEVICE_ELECTRICITY_VALUE),
                            object : ICommandResponse<BatteryRsp> {
                                override fun onDataResponse(resultEntity: BatteryRsp) {
                                    metrics["battery"] = resultEntity.batteryValue
                                }
                            }
                        )
                        result.success(metrics)
                    } catch (e: Exception) {
                        result.error("METRICS_ERROR", e.message, null)
                    }
                }

                "startHeartRateNotifications" -> {
                    // Pornește stream-ul mock (sau abonează-te la SDK-ul real)
                    startMockHrStream()
                    result.success(null)
                }

                "stopHeartRateNotifications" -> {
                    stopMockHrStream()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // EventChannel pentru HR live
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HR_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    hrSink = events
                }
                override fun onCancel(arguments: Any?) {
                    hrSink = null
                }
            }
        )
    }

    private fun startMockHrStream() {
        stopMockHrStream()
        hrTimer = java.util.Timer()
        var bpm = 70
        hrTimer?.scheduleAtFixedRate(object : java.util.TimerTask() {
            override fun run() {
                bpm += listOf(-1, 0, 1).random()
                val value = bpm
                // IMPORTANT: trimite evenimentul pe thread-ul principal
                mainHandler.post {
                    hrSink?.success(value)
                }
            }
        }, 500L, 1500L)
    }

    private fun stopMockHrStream() {
        hrTimer?.cancel()
        hrTimer = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopMockHrStream()
    }
}
