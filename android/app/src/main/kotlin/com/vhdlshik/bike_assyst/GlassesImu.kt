package com.vhdlshik.bike_assyst

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Streams raw motion-sensor reports from XREAL/Nreal Air glasses over USB.
 *
 * Only transport lives here: find the glasses, get USB permission, claim the
 * sensor's HID interface, send the enable command Dart built, and forward
 * reports. Decoding is in lib/head/xreal_air.dart. Reports are batched into
 * fixed-size slots every [BATCH_MS] so ~1000 reports a second don't each
 * cross the platform channel.
 */
class GlassesImu(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val VENDOR_ID = 0x3318
        // Product id -> HID interface carrying the sensor.
        private val IMU_INTERFACE = mapOf(0x0424 to 3, 0x0428 to 3, 0x0432 to 3, 0x0426 to 2)
        private const val ACTION_PERMISSION = "com.vhdlshik.bike_assyst.USB_PERMISSION"
        private const val TIMEOUT_MS = 250
        private const val BATCH_MS = 20L
        // HID class request to send a report over the control pipe.
        private const val HID_SET_REPORT = 0x09
    }

    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var connection: UsbDeviceConnection? = null
    private var iface: UsbInterface? = null
    private var outEndpoint: UsbEndpoint? = null
    @Volatile private var running = false
    private var reader: Thread? = null

    init {
        MethodChannel(messenger, "bike_assyst/glasses_imu").setMethodCallHandler(this)
        EventChannel(messenger, "bike_assyst/glasses_imu/reports").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<ByteArray>("command")!!, call.argument<Int>("packetSize")!!, result)
            "stop" -> {
                stop(call.argument<ByteArray>("command"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Replies null once streaming, or a message saying why not. */
    private fun start(command: ByteArray, packetSize: Int, result: MethodChannel.Result) {
        stop(null)
        val device = usb.deviceList.values.firstOrNull {
            it.vendorId == VENDOR_ID && IMU_INTERFACE.containsKey(it.productId)
        }
        if (device == null) {
            result.success("No XREAL Air glasses connected")
            return
        }
        if (usb.hasPermission(device)) {
            result.success(open(device, command, packetSize))
            return
        }
        requestPermission(device) { granted ->
            result.success(if (granted) open(device, command, packetSize) else "USB permission for the glasses was denied")
        }
    }

    private fun requestPermission(device: UsbDevice, done: (Boolean) -> Unit) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                context.unregisterReceiver(this)
                done(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        val filter = IntentFilter(ACTION_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        // The system fills in the result extras, so the intent must be mutable;
        // naming our package keeps a mutable intent safe.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(ACTION_PERMISSION).setPackage(context.packageName)
        usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    private fun open(device: UsbDevice, command: ByteArray, packetSize: Int): String? {
        val number = IMU_INTERFACE.getValue(device.productId)
        val found = (0 until device.interfaceCount).map { device.getInterface(it) }.firstOrNull { it.id == number }
            ?: return "Glasses have no motion-sensor interface"
        val endpoints = (0 until found.endpointCount).map { found.getEndpoint(it) }
        val inEndpoint = endpoints.firstOrNull { it.direction == UsbConstants.USB_DIR_IN }
            ?: return "Glasses' motion sensor has no input endpoint"
        val conn = usb.openDevice(device) ?: return "Could not open the glasses"
        // Take the interface from the system HID driver.
        if (!conn.claimInterface(found, true)) {
            conn.close()
            return "Could not claim the glasses' motion sensor"
        }
        connection = conn
        iface = found
        outEndpoint = endpoints.firstOrNull { it.direction == UsbConstants.USB_DIR_OUT }
        if (!write(command)) {
            stop(null)
            return "Glasses did not accept the motion-sensor command"
        }
        running = true
        reader = Thread({ readLoop(conn, inEndpoint, maxOf(packetSize, inEndpoint.maxPacketSize), packetSize) }, "glasses-imu")
            .apply { start() }
        return null
    }

    private fun write(packet: ByteArray): Boolean {
        val conn = connection ?: return false
        val out = outEndpoint
        val sent = if (out != null) {
            conn.bulkTransfer(out, packet, packet.size, TIMEOUT_MS)
        } else {
            // No interrupt-out endpoint: send as an output report on the control pipe.
            val type = UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_CLASS or 0x01 // to interface
            conn.controlTransfer(type, HID_SET_REPORT, 0x0200, iface!!.id, packet, packet.size, TIMEOUT_MS)
        }
        return sent == packet.size
    }

    private fun readLoop(conn: UsbDeviceConnection, endpoint: UsbEndpoint, readSize: Int, slot: Int) {
        val buffer = ByteArray(readSize)
        val batch = ByteArrayOutputStream()
        var lastFlush = System.currentTimeMillis()
        while (running) {
            val n = conn.bulkTransfer(endpoint, buffer, buffer.size, TIMEOUT_MS)
            if (n > 0) {
                // One report per fixed-size slot, cut or zero-padded.
                batch.write(buffer, 0, minOf(n, slot))
                repeat(slot - minOf(n, slot)) { batch.write(0) }
            } else if (n < 0 && usb.deviceList.values.none { it.vendorId == VENDOR_ID }) {
                main.post { sink?.error("unplugged", "Glasses unplugged", null) }
                break
            }
            val now = System.currentTimeMillis()
            if (batch.size() > 0 && now - lastFlush >= BATCH_MS) {
                val bytes = batch.toByteArray()
                batch.reset()
                lastFlush = now
                main.post { sink?.success(bytes) }
            }
        }
    }

    private fun stop(command: ByteArray?) {
        running = false
        reader?.join(TIMEOUT_MS * 2L)
        reader = null
        if (command != null) write(command)
        val conn = connection
        iface?.let { conn?.releaseInterface(it) }
        conn?.close()
        connection = null
        iface = null
        outEndpoint = null
    }
}
