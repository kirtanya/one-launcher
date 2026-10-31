package com.kirtanya.one_launcher

import android.content.Context
import android.content.Intent
import com.google.home.ConnectivityState
import com.google.home.DeviceType
import com.google.home.FactoryRegistry
import com.google.home.Home
import com.google.home.HomeClient
import com.google.home.HomeConfig
import com.google.home.HomeDevice
import com.google.home.HomeException
import com.google.home.PermissionsResultStatus
import com.google.home.PermissionsState
import com.google.home.google.ExtendedColorControl
import com.google.home.google.GoogleAirCoolerDevice
import com.google.home.matter.standard.ColorControl
import com.google.home.matter.standard.ColorTemperatureLightDevice
import com.google.home.matter.standard.DimmableLightDevice
import com.google.home.matter.standard.DimmablePlugInUnitDevice
import com.google.home.matter.standard.ExtendedColorLightDevice
import com.google.home.matter.standard.FanControl
import com.google.home.matter.standard.FanDevice
import com.google.home.matter.standard.HeatingCoolingUnitDevice
import com.google.home.matter.standard.LevelControl
import com.google.home.matter.standard.LevelControlTrait
import com.google.home.matter.standard.OnOff
import com.google.home.matter.standard.OnOffLightDevice
import com.google.home.matter.standard.OnOffPluginUnitDevice
import com.google.home.matter.standard.RelativeHumidityMeasurement
import com.google.home.matter.standard.RoomAirConditionerDevice
import com.google.home.matter.standard.TemperatureMeasurement
import com.google.home.matter.standard.Thermostat
import com.google.home.matter.standard.ThermostatDevice
import com.google.home.matter.standard.ThermostatTrait
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

/**
 * Smart home (phone flavour): the `one_launcher/home` channel (contract in lib/smart_home.dart)
 * on top of Google's Home APIs SDK. MainActivity calls [attach] reflectively so the TV flavour,
 * which doesn't compile this source set, still builds.
 */
object SmartHomeBridge {
    private const val CHANNEL = "one_launcher/home"

    private var app: Context? = null
    private var home: HomeClient? = null
    private var channel: MethodChannel? = null
    private var scope: CoroutineScope? = null
    private var streaming: Job? = null
    private var flowDone: CompletableDeferred<String?>? = null

    // Live state, filled by the streaming coroutines.
    private val devices = ConcurrentHashMap<String, HomeDevice>()
    private val types = ConcurrentHashMap<String, Set<DeviceType>>()
    @Volatile private var rooms: Map<String, String> = emptyMap()
    private val dirty = Channel<Unit>(Channel.CONFLATED)

    private val registry by lazy {
        FactoryRegistry(
            traits = listOf(OnOff, LevelControl, ColorControl, ExtendedColorControl, Thermostat, FanControl,
                TemperatureMeasurement, RelativeHumidityMeasurement),
            types = listOf(OnOffLightDevice, DimmableLightDevice, ColorTemperatureLightDevice, ExtendedColorLightDevice,
                OnOffPluginUnitDevice, DimmablePlugInUnitDevice, RoomAirConditionerDevice, ThermostatDevice,
                HeatingCoolingUnitDevice, GoogleAirCoolerDevice, FanDevice),
        )
    }

    @JvmStatic
    fun attach(engine: FlutterEngine, context: Context) {
        val ctx = context.applicationContext
        app = ctx
        // Any error inside the bridge is logged, never allowed to crash the launcher.
        val guard = CoroutineExceptionHandler { _, e -> android.util.Log.w("SmartHome", "bridge error", e) }
        val sc = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + guard)
        scope = sc
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result -> handle(sc, call, result) }
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}
            override fun onEngineWillDestroy() {
                if (channel === ch) {
                    ch.setMethodCallHandler(null)
                    channel = null
                    streaming = null
                    scope = null
                }
                sc.cancel()
            }
        })
        // Already granted earlier? Start streaming straight away.
        sc.launch { if (permissionState() == true) startStreaming() }
    }

    internal fun client(): HomeClient? = home ?: app?.let { ctx ->
        runCatching { Home.getClient(ctx, HomeConfig(coroutineContext = Dispatchers.IO, factoryRegistry = registry)) }
            .getOrNull()?.also { home = it }
    }

    internal suspend fun requestPermissions(client: HomeClient): String? {
        val r = try {
            client.requestPermissions()
        } catch (e: HomeException) {
            return e.message ?: "Google Home refused"
        }
        return when (r.status) {
            PermissionsResultStatus.SUCCESS -> null
            PermissionsResultStatus.CANCELLED -> "cancelled"
            else -> r.errorMessage ?: "Google Home permission error"
        }
    }

    internal fun permissionFlowDone(error: String?) {
        flowDone?.complete(error)
    }

    /** true = granted, false = not granted. */
    private suspend fun permissionState(): Boolean {
        val c = client() ?: return false
        val s = withTimeoutOrNull(8000) {
            c.hasPermissions().first { it != PermissionsState.PERMISSIONS_STATE_UNINITIALIZED }
        } ?: return false
        return when (s) {
            PermissionsState.GRANTED -> true
            PermissionsState.PERMISSIONS_STATE_UNAVAILABLE ->
                // The platform can't say: any visible device means access exists.
                runCatching { c.devices().list().isNotEmpty() }.getOrDefault(false)
            else -> false
        }
    }

    private fun handle(sc: CoroutineScope, call: MethodCall, result: MethodChannel.Result) {
        sc.launch {
            try {
                when (call.method) {
                    "status" -> {
                        val ok = permissionState()
                        if (ok) startStreaming()
                        result.success(if (ok) "ready" else "signedOut")
                    }
                    "connect" -> {
                        val ctx = app ?: throw IllegalStateException("Smart home isn't ready")
                        if (!permissionState()) {
                            val done = CompletableDeferred<String?>()
                            flowDone = done
                            ctx.startActivity(Intent(ctx, HomeConnectActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            val error = done.await()
                            flowDone = null
                            if (error != null && error != "cancelled") throw IllegalStateException(error)
                        }
                        val ok = permissionState()
                        if (ok) startStreaming()
                        result.success(if (ok) "ready" else "signedOut")
                    }
                    "devices" -> {
                        startStreaming()
                        // First call right after connecting: give the first emission a moment.
                        if (devices.isEmpty()) {
                            runCatching { client()!!.devices().list().forEach { devices[it.id.id] = it } }
                            for (d in devices.values) if (types[d.id.id] == null) {
                                withTimeoutOrNull(3000) { types[d.id.id] = d.types().first() }
                            }
                        }
                        result.success(snapshot())
                    }
                    "set" -> {
                        set(call.argument<String>("id")!!, call.argument<String>("trait")!!, call.argument<Any>("value"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result.error("home", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    // ---- streaming ----

    private fun startStreaming() {
        val sc = scope ?: return
        if (streaming?.isActive == true) return
        val c = client() ?: return
        streaming = sc.launch {
            launch {
                c.rooms().collect { set ->
                    rooms = set.associate { it.id.id to it.name }
                    dirty.trySend(Unit)
                }
            }
            launch {
                val watchers = HashMap<String, Job>()
                c.devices().collect { set ->
                    val ids = set.map { it.id.id }.toSet()
                    for (d in set) {
                        devices[d.id.id] = d
                        if (watchers[d.id.id]?.isActive != true) {
                            watchers[d.id.id] = launch {
                                d.types().collect { t ->
                                    types[d.id.id] = t
                                    dirty.trySend(Unit)
                                }
                            }
                        }
                    }
                    for (gone in watchers.keys - ids) {
                        watchers.remove(gone)?.cancel()
                        devices.remove(gone)
                        types.remove(gone)
                    }
                    dirty.trySend(Unit)
                }
            }
            launch { pushLoop() }
        }
    }

    @OptIn(FlowPreview::class)
    private suspend fun pushLoop() {
        dirty.receiveAsFlow().debounce(150).collect {
            channel?.invokeMethod("homeChanged", snapshot())
        }
    }

    // ---- reading ----

    private fun snapshot(): List<Map<String, Any?>> =
        devices.values.mapNotNull { d -> types[d.id.id]?.let { describe(d, it) } }
            .sortedWith(compareBy({ it["room"] as String }, { it["name"] as String }))

    private fun describe(d: HomeDevice, ts: Set<DeviceType>): Map<String, Any?>? {
        var kind: String? = null
        var onOff: OnOff? = null
        var level: LevelControl? = null
        var color: ColorControl? = null
        var thermo: Thermostat? = null
        for (t in ts) {
            when (t) {
                is ExtendedColorLightDevice -> { kind = "light"; onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl; color = t.standardTraits.colorControl }
                is ColorTemperatureLightDevice -> { kind = "light"; onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl; color = t.standardTraits.colorControl }
                is DimmableLightDevice -> { kind = "light"; onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
                is OnOffLightDevice -> { kind = "light"; onOff = t.standardTraits.onOff }
                is DimmablePlugInUnitDevice -> { kind = "plug"; onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
                is OnOffPluginUnitDevice -> { kind = "plug"; onOff = t.standardTraits.onOff }
                is RoomAirConditionerDevice -> { kind = "ac"; onOff = t.standardTraits.onOff; thermo = t.standardTraits.thermostat }
                is GoogleAirCoolerDevice -> { kind = "ac"; onOff = t.standardTraits.onOff; thermo = t.standardTraits.thermostat }
                is ThermostatDevice -> { if (kind == null) kind = "ac"; thermo = t.standardTraits.thermostat }
                is HeatingCoolingUnitDevice -> { if (kind == null) kind = "ac"; onOff = t.standardTraits.onOff }
                is FanDevice -> { if (kind == null) kind = "fan"; onOff = t.standardTraits.onOff }
                else -> {}
            }
        }
        if (kind == null) return null
        val sysMode = thermo?.systemMode
        val on = onOff?.onOff ?: (sysMode != null && sysMode != ThermostatTrait.SystemModeEnum.Off)
        val m = mutableMapOf<String, Any?>(
            "id" to d.id.id,
            "name" to d.name,
            "room" to (d.roomId?.id?.let { rooms[it] } ?: ""),
            "type" to kind,
            "online" to (d.sourceConnectivity.connectivityState != ConnectivityState.OFFLINE),
            "on" to on,
        )
        level?.currentLevel?.let { m["brightness"] = (it.toInt() * 100 / 254.0).roundToInt().coerceIn(0, 100) }
        if (kind == "ac" && thermo != null) {
            val heat = sysMode == ThermostatTrait.SystemModeEnum.Heat || sysMode == ThermostatTrait.SystemModeEnum.EmergencyHeat
            val sp = if (heat) thermo.occupiedHeatingSetpoint ?: thermo.occupiedCoolingSetpoint
            else thermo.occupiedCoolingSetpoint ?: thermo.occupiedHeatingSetpoint
            sp?.let { m["setpoint"] = it / 100.0 } // Matter: 0.01 °C
            m["mode"] = if (!on) "off" else modeName(sysMode)
        }
        return m
    }

    private fun modeName(s: ThermostatTrait.SystemModeEnum?): String? = when (s) {
        ThermostatTrait.SystemModeEnum.Off -> "off"
        ThermostatTrait.SystemModeEnum.Auto -> "auto"
        ThermostatTrait.SystemModeEnum.Cool, ThermostatTrait.SystemModeEnum.Precooling,
        ThermostatTrait.SystemModeEnum.Dry, ThermostatTrait.SystemModeEnum.Sleep -> "cool"
        ThermostatTrait.SystemModeEnum.Heat, ThermostatTrait.SystemModeEnum.EmergencyHeat -> "heat"
        ThermostatTrait.SystemModeEnum.FanOnly -> "fan"
        else -> null
    }

    // ---- commands ----

    private suspend fun set(id: String, trait: String, value: Any?) {
        val d = devices[id] ?: client()!!.devices().list().firstOrNull { it.id.id == id }
            ?: throw IllegalStateException("Device not found")
        val ts = types[id] ?: d.types().first()
        var onOff: OnOff? = null
        var level: LevelControl? = null
        var thermo: Thermostat? = null
        for (t in ts) when (t) {
            is ExtendedColorLightDevice -> { onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
            is ColorTemperatureLightDevice -> { onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
            is DimmableLightDevice -> { onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
            is OnOffLightDevice -> onOff = t.standardTraits.onOff
            is DimmablePlugInUnitDevice -> { onOff = t.standardTraits.onOff; level = t.standardTraits.levelControl }
            is OnOffPluginUnitDevice -> onOff = t.standardTraits.onOff
            is RoomAirConditionerDevice -> { onOff = t.standardTraits.onOff; thermo = t.standardTraits.thermostat }
            is GoogleAirCoolerDevice -> { onOff = t.standardTraits.onOff; thermo = t.standardTraits.thermostat }
            is ThermostatDevice -> thermo = t.standardTraits.thermostat
            is HeatingCoolingUnitDevice -> onOff = t.standardTraits.onOff
            is FanDevice -> onOff = t.standardTraits.onOff
            else -> {}
        }
        try {
            when (trait) {
                "on" -> {
                    val on = value as Boolean
                    when {
                        onOff != null -> if (on) onOff.on() else onOff.off()
                        thermo != null -> setMode(null, thermo, if (on) "cool" else "off")
                        else -> throw IllegalStateException("${d.name} can't be switched")
                    }
                }
                "brightness" -> {
                    val lc = level ?: throw IllegalStateException("${d.name} can't be dimmed")
                    val pct = (value as Number).toInt().coerceIn(0, 100)
                    lc.moveToLevelWithOnOff((pct * 254 / 100.0).roundToInt().toUByte(), null, LevelControlTrait.OptionsBitmap(), LevelControlTrait.OptionsBitmap())
                }
                "setpoint" -> {
                    val th = thermo ?: throw IllegalStateException("${d.name} has no temperature setting")
                    val c = ((value as Number).toDouble() * 100).roundToInt().toShort()
                    val heat = th.systemMode.let { it == ThermostatTrait.SystemModeEnum.Heat || it == ThermostatTrait.SystemModeEnum.EmergencyHeat }
                    th.update { if (heat) setOccupiedHeatingSetpoint(c) else setOccupiedCoolingSetpoint(c) }
                }
                "mode" -> setMode(onOff, thermo ?: throw IllegalStateException("${d.name} has no modes"), value as String)
                else -> throw IllegalStateException("Unknown setting $trait")
            }
        } catch (e: HomeException) {
            throw IllegalStateException(e.message ?: "Google Home refused the command")
        }
    }

    private suspend fun setMode(onOff: OnOff?, th: Thermostat, mode: String) {
        if (mode == "off") {
            if (onOff != null) onOff.off() else th.update { setSystemMode(ThermostatTrait.SystemModeEnum.Off) }
            return
        }
        val sm = when (mode) {
            "cool" -> ThermostatTrait.SystemModeEnum.Cool
            "heat" -> ThermostatTrait.SystemModeEnum.Heat
            "auto" -> ThermostatTrait.SystemModeEnum.Auto
            "fan" -> ThermostatTrait.SystemModeEnum.FanOnly
            else -> throw IllegalStateException("Unknown mode $mode")
        }
        th.update { setSystemMode(sm) }
        if (onOff != null && onOff.onOff != true) onOff.on()
    }
}
