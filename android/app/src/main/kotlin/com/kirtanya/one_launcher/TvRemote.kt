package com.kirtanya.one_launcher

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.math.BigInteger
import java.net.InetSocketAddress
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey
import java.util.Date
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509ExtendedTrustManager
import javax.security.auth.x500.X500Principal

/**
 * TV remote for Google TV / Android TV, over the TV's own "Android TV Remote" protocol (v2) —
 * the one the Google TV and Google Home apps use. Everything stays on the local network:
 *
 *  - find: mDNS service `_androidtvremote2._tcp` (or the user types the TV's IP address)
 *  - pair once (TLS, port 6467): the TV shows a 6-character code; we answer with a hash of both
 *    sides' certificates + that code. Our certificate lives in the Android Keystore.
 *  - remote (TLS, port 6466): key presses, app links; the TV pings us, we answer.
 *
 * The TV's certificate is pinned after pairing, so a different device at the same address
 * can't pose as the TV.
 */
class TvRemote(private val context: Context, private val events: () -> MethodChannel?) {
    companion object {
        private const val ALIAS = "one_launcher_tv_remote"
        private const val PAIR_PORT = 6467
        private const val REMOTE_PORT = 6466
        private const val SERVICE = "_androidtvremote2._tcp."
        private const val FEATURES = 622 // ping, key, IME, power, volume, app links
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val prefs = context.getSharedPreferences("tv_remote", Context.MODE_PRIVATE)

    private var pairSocket: SSLSocket? = null
    private var pairHost: String? = null
    private var socket: SSLSocket? = null
    private var out: OutputStream? = null
    private var host: String? = null
    @Volatile private var lastServerCert: X509Certificate? = null

    // Typing on the TV: the TV's counters for the focused text field (it ignores edits without them).
    private var imeCounter = 0L
    private var fieldCounter = 0L

    /** The TV told us about a text field with its counters (key inject with a field, a batch
     *  edit, or a show-keyboard request). Some TVs only name the app: then typing goes as keys. */
    @Volatile private var imeReady = false

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "tvDiscover" -> discover(result)
            "tvPairStart" -> io.execute { reply(result) { pairStart(call.argument<String>("host")!!) } }
            "tvPairFinish" -> io.execute { reply(result) { pairFinish(call.argument<String>("code")!!) } }
            "tvConnect" -> io.execute { reply(result) { connect(call.argument<String>("host")!!) } }
            "tvKey" -> io.execute { reply(result) { key(call.argument<Int>("code")!!, call.argument<Int>("direction") ?: 3) } }
            "tvAppLink" -> io.execute { reply(result) { appLink(call.argument<String>("link")!!) } }
            "tvText" -> io.execute { reply(result) { text(call.argument<String>("text") ?: "") } }
            "tvDisconnect" -> io.execute { reply(result) { disconnect(); true } }
            "tvForget" -> io.execute { reply(result) { disconnect(); prefs.edit().remove("pin:" + (call.argument<String>("host") ?: "")).apply(); true } }
            else -> return false
        }
        return true
    }

    /** Runs [work] on the remote thread and answers Flutter on the main thread (errors as messages). */
    private fun reply(result: MethodChannel.Result, work: () -> Any?) {
        try {
            val v = work()
            main.post { result.success(v) }
        } catch (e: Exception) {
            main.post { result.error("tv", e.message ?: e.javaClass.simpleName, null) }
        }
    }

    private fun emit(state: String, extra: Map<String, Any?> = emptyMap()) {
        main.post { events()?.invokeMethod("tvState", mapOf("state" to state, "host" to host) + extra) }
    }

    // ---- Discovery -----------------------------------------------------------------------

    /** TVs announcing the remote service on this Wi-Fi, collected for ~3 s: [{name, host}]. */
    private fun discover(result: MethodChannel.Result) {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val found = linkedMapOf<String, Map<String, Any>>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(r: NsdServiceInfo) {
                        val ip = (if (Build.VERSION.SDK_INT >= 34) r.hostAddresses.firstOrNull() else @Suppress("DEPRECATION") r.host)?.hostAddress ?: return
                        synchronized(found) { found[ip] = mapOf("name" to r.serviceName, "host" to ip) }
                    }
                    override fun onResolveFailed(r: NsdServiceInfo, code: Int) {}
                })
            }
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) {}
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        }
        try {
            nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            result.success(emptyList<Any>())
            return
        }
        main.postDelayed({
            try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) {}
            result.success(synchronized(found) { found.values.toList() })
        }, 3500)
    }

    // ---- TLS with our keystore certificate -----------------------------------------------

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun ensureKey() {
        if (keyStore().containsAlias(ALIAS)) return
        val now = System.currentTimeMillis()
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
        kpg.initialize(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(2048)
                .setDigests(
                    KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA1, KeyProperties.DIGEST_SHA256,
                    KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512,
                )
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1, KeyProperties.SIGNATURE_PADDING_RSA_PSS)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE, KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                .setCertificateSubject(X500Principal("CN=atvremote, O=One Launcher"))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - 86_400_000L))
                .setCertificateNotAfter(Date(now + 20L * 365 * 86_400_000L))
                .build(),
        )
        kpg.generateKeyPair()
    }

    private fun clientCert(): X509Certificate = keyStore().getCertificate(ALIAS) as X509Certificate

    private fun open(host: String, port: Int): SSLSocket {
        ensureKey()
        val ks = keyStore()
        val keys = object : X509ExtendedKeyManager() {
            override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(ALIAS)
            override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = ALIAS
            override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = ALIAS
            override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
            override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
            override fun getCertificateChain(alias: String?) = arrayOf(ks.getCertificate(ALIAS) as X509Certificate)
            override fun getPrivateKey(alias: String?) = ks.getKey(ALIAS, null) as PrivateKey
        }
        // The TV's certificate is self-signed: accept it here and pin it after pairing.
        val trust = object : X509ExtendedTrustManager() {
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?, socket: Socket?) { lastServerCert = chain[0] }
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?, engine: SSLEngine?) { lastServerCert = chain[0] }
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) { lastServerCert = chain[0] }
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) {}
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) {}
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val ssl = SSLContext.getInstance("TLS").apply { init(arrayOf(keys), arrayOf(trust), null) }
        val raw = Socket().apply { connect(InetSocketAddress(host, port), 4000); soTimeout = 0 }
        val s = ssl.socketFactory.createSocket(raw, host, port, true) as SSLSocket
        s.startHandshake()
        return s
    }

    private fun fingerprint(c: X509Certificate) = MessageDigest.getInstance("SHA-256").digest(c.encoded).joinToString("") { "%02x".format(it) }

    // ---- Pairing (port 6467) -------------------------------------------------------------

    /** Starts pairing: afterwards the TV shows a 6-character code. */
    private fun pairStart(h: String): Boolean {
        pairSocket?.close()
        val s = open(h, PAIR_PORT)
        pairSocket = s
        pairHost = h
        val o = s.outputStream
        val i = s.inputStream
        fun outer(build: Pb.() -> Unit) = Pb().apply { int(1, 2); int(2, 200); build() }
        send(o, outer { msg(10, Pb().str(1, "atvremote").str(2, "One Launcher (${Build.MODEL})")) })
        expectOk(read(i))
        // Hex code of 6 characters, we type it in (input role).
        send(o, outer { msg(20, Pb().msg(1, Pb().int(1, 3).int(2, 6)).int(3, 1)) })
        expectOk(read(i))
        send(o, outer { msg(30, Pb().msg(1, Pb().int(1, 3).int(2, 6)).int(2, 1)) })
        expectOk(read(i))
        return true
    }

    /** Finishes pairing with the code on the TV screen; pins the TV's certificate. */
    private fun pairFinish(code: String): Boolean {
        val s = pairSocket ?: throw IllegalStateException("Start pairing first")
        val c = code.trim().uppercase()
        require(c.length == 6 && c.all { it.isDigit() || it in 'A'..'F' }) { "The code is 6 characters (0-9, A-F)" }
        val server = s.session.peerCertificates[0] as X509Certificate
        val cKey = clientCert().publicKey as RSAPublicKey
        val sKey = server.publicKey as RSAPublicKey
        val sha = MessageDigest.getInstance("SHA-256")
        sha.update(unsigned(cKey.modulus)); sha.update(unsigned(cKey.publicExponent))
        sha.update(unsigned(sKey.modulus)); sha.update(unsigned(sKey.publicExponent))
        sha.update(hex(c.substring(2)))
        val hash = sha.digest()
        if ((hash[0].toInt() and 0xff) != c.substring(0, 2).toInt(16)) throw IllegalArgumentException("That code doesn't match the TV")
        send(s.outputStream, Pb().apply { int(1, 2); int(2, 200); msg(40, Pb().bytes(1, hash)) })
        expectOk(read(s.inputStream))
        prefs.edit().putString("pin:" + pairHost, fingerprint(server)).apply()
        s.close()
        pairSocket = null
        return true
    }

    private fun unsigned(n: BigInteger): ByteArray {
        val b = n.toByteArray()
        return if (b.size > 1 && b[0] == 0.toByte()) b.copyOfRange(1, b.size) else b
    }

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun expectOk(m: Map<Int, List<Any>>) {
        val status = (m[2]?.firstOrNull() as? Long)?.toInt() ?: 200
        if (status != 200) throw IllegalStateException(if (status == 402) "That code doesn't match the TV" else "The TV said no ($status)")
    }

    // ---- Remote (port 6466) --------------------------------------------------------------

    private fun connect(h: String): Boolean {
        disconnect()
        val pin = prefs.getString("pin:$h", null) ?: throw IllegalStateException("not paired")
        host = h
        emit("connecting")
        val s = open(h, REMOTE_PORT)
        val server = lastServerCert
        if (server == null || fingerprint(server) != pin) {
            s.close()
            throw IllegalStateException("This isn't the TV you paired with — pair again")
        }
        socket = s
        out = s.outputStream
        val input = s.inputStream
        Thread({ readLoop(s, input) }, "tv-remote").start()
        return true
    }

    private fun readLoop(s: SSLSocket, input: InputStream) {
        try {
            while (!s.isClosed) {
                val m = read(input)
                when {
                    m.containsKey(1) -> { // configure → tell the TV who we are and what we can do
                        val info = Pb().str(1, Build.MODEL).str(2, Build.MANUFACTURER).int(3, 1).str(4, "1").str(5, "atvremote").str(6, "1.0.0")
                        write(Pb().msg(1, Pb().int(1, FEATURES.toLong()).msg(2, info)))
                    }
                    m.containsKey(2) -> { // set active
                        write(Pb().msg(2, Pb().int(1, FEATURES.toLong())))
                        emit("connected")
                    }
                    m.containsKey(8) -> { // ping → pong
                        val ping = Pb.parse(m[8]!!.first() as ByteArray)
                        write(Pb().msg(9, Pb().int(1, (ping[1]?.firstOrNull() as? Long) ?: 0)))
                    }
                    m.containsKey(50) -> { // volume level
                        val v = Pb.parse(m[50]!!.first() as ByteArray)
                        emit(
                            "volume",
                            mapOf(
                                "max" to ((v[6]?.firstOrNull() as? Long) ?: 0).toInt(),
                                "level" to ((v[7]?.firstOrNull() as? Long) ?: 0).toInt(),
                                "muted" to (((v[8]?.firstOrNull() as? Long) ?: 0) != 0L),
                            ),
                        )
                    }
                    m.containsKey(40) -> { // TV on/off
                        val st = Pb.parse(m[40]!!.first() as ByteArray)
                        emit("power", mapOf("on" to (((st[1]?.firstOrNull() as? Long) ?: 0) != 0L)))
                    }
                    m.keys.any { it in 20..22 } -> imeMessage(m)
                    m.containsKey(3) -> emit("error", mapOf("message" to "The TV reported an error"))
                }
            }
        } catch (_: Exception) {
        }
        if (socket === s) {
            socket = null
            out = null
            emit("disconnected")
        }
    }

    /** Typing messages from the TV: 20 = IME key inject (app + field), 21 = batch edit (the TV's
     *  own edits: counters), 22 = show keyboard. Logged (tag TvRemote) to debug typing. */
    private fun imeMessage(m: Map<Int, List<Any>>) {
        Log.i("TvRemote", "IME in: " + m.mapValues { (_, v) -> v.map { if (it is ByteArray) describe(Pb.parse(it)) else it } })
        m[20]?.firstOrNull()?.let { raw ->
            val k = Pb.parse(raw as ByteArray)
            (k[1]?.firstOrNull() as? ByteArray)?.let { app -> imeCounter = (Pb.parse(app)[1]?.firstOrNull() as? Long) ?: imeCounter }
            (k[2]?.firstOrNull() as? ByteArray)?.let { field ->
                imeReady = true
                emitIme(Pb.parse(field))
            }
        }
        // 21 from the TV is only its keyboard's on/off state ({1=1, 2=1} shown, {1=0} hidden) — not
        // the counters: taking them made the TV drop every edit ("input field has changed from 1
        // to 43"). The counters come from 20 (the app's counter) and 20/22 (the field's).
        if (m.containsKey(21)) imeReady = imeReady || imeCounter != 0L
        m[22]?.firstOrNull()?.let { raw ->
            val req = Pb.parse(raw as ByteArray)
            (req[2]?.firstOrNull() as? ByteArray)?.let { field ->
                imeReady = true
                emitIme(Pb.parse(field))
            } ?: emit("ime", mapOf("text" to "", "label" to ""))
        }
        Log.i("TvRemote", "IME counters now ime=$imeCounter field=$fieldCounter")
    }

    /** Readable dump of a parsed message (nested messages tried as messages, else text). */
    private fun describe(m: Map<Int, List<Any>>): String = m.entries.joinToString(", ", "{", "}") { (k, v) ->
        "$k=" + v.joinToString("|") { x ->
            if (x is ByteArray) {
                val s = x.toString(Charsets.UTF_8)
                if (s.all { it.isLetterOrDigit() || it in " .-_:/" }) "\"$s\"" else try { describe(Pb.parse(x)) } catch (_: Exception) { "bytes(${x.size})" }
            } else x.toString()
        }
    }

    /** Text field status from the TV: counter, current text, label → Flutter shows the keyboard. */
    private fun emitIme(f: Map<Int, List<Any>>) {
        fieldCounter = (f[1]?.firstOrNull() as? Long) ?: fieldCounter
        val value = (f[2]?.firstOrNull() as? ByteArray)?.toString(Charsets.UTF_8) ?: ""
        val label = (f[6]?.firstOrNull() as? ByteArray)?.toString(Charsets.UTF_8) ?: ""
        emit("ime", mapOf("text" to value, "label" to label))
    }

    /** Replace the TV's focused text field with [value] (sent whole on each change). Returns
     *  false — sending nothing — when the TV hasn't given us a field: Flutter types keys instead. */
    private fun text(value: String): Boolean {
        if (!imeReady) {
            Log.i("TvRemote", "IME out skipped (no field from the TV): typing as keys")
            return false
        }
        val pos = (value.length - 1).toLong()
        val obj = Pb().int(1, pos).int(2, pos).str(3, value)
        val edit = Pb().int(1, 1).msg(2, obj)
        Log.i("TvRemote", "IME out: ime=$imeCounter field=$fieldCounter text=\"$value\"")
        write(Pb().msg(21, Pb().int(1, imeCounter).int(2, fieldCounter).msg(3, edit)))
        return true
    }

    private fun key(code: Int, direction: Int): Boolean {
        write(Pb().msg(10, Pb().int(1, code.toLong()).int(2, direction.toLong())))
        return true
    }

    private fun appLink(link: String): Boolean {
        write(Pb().msg(90, Pb().str(1, link)))
        return true
    }

    private fun disconnect() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        out = null
    }

    @Synchronized
    private fun write(m: Pb) {
        val o = out ?: throw IllegalStateException("not connected")
        send(o, m)
    }

    // ---- Framing: varint length + protobuf ------------------------------------------------

    private fun send(o: OutputStream, m: Pb) {
        val body = m.bytes()
        val frame = ByteArrayOutputStream()
        Pb.writeVarint(frame, body.size.toLong())
        frame.write(body)
        o.write(frame.toByteArray())
        o.flush()
    }

    private fun read(i: InputStream): Map<Int, List<Any>> {
        var len = 0L
        var shift = 0
        while (true) {
            val b = i.read()
            if (b < 0) throw EOFException()
            len = len or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) break
            shift += 7
        }
        val buf = ByteArray(len.toInt())
        var got = 0
        while (got < buf.size) {
            val n = i.read(buf, got, buf.size - got)
            if (n < 0) throw EOFException()
            got += n
        }
        return Pb.parse(buf)
    }
}

/** A tiny protobuf writer/reader: varints and length-delimited fields are all this protocol uses. */
class Pb {
    private val b = ByteArrayOutputStream()

    fun int(field: Int, v: Long) = apply { writeVarint(b, (field shl 3).toLong()); writeVarint(b, v) }
    fun bytes(field: Int, data: ByteArray) = apply { writeVarint(b, ((field shl 3) or 2).toLong()); writeVarint(b, data.size.toLong()); b.write(data) }
    fun str(field: Int, s: String) = bytes(field, s.toByteArray())
    fun msg(field: Int, m: Pb) = bytes(field, m.bytes())
    fun bytes(): ByteArray = b.toByteArray()

    companion object {
        fun writeVarint(o: ByteArrayOutputStream, value: Long) {
            var v = value
            while (true) {
                if (v and 0x7fL.inv() == 0L) { o.write(v.toInt()); return }
                o.write(((v and 0x7f) or 0x80).toInt())
                v = v ushr 7
            }
        }

        /** field number → values (Long for varints, ByteArray for length-delimited). */
        fun parse(data: ByteArray): Map<Int, List<Any>> {
            val out = mutableMapOf<Int, MutableList<Any>>()
            var p = 0
            fun varint(): Long {
                var r = 0L
                var s = 0
                while (true) {
                    val x = data[p++].toInt() and 0xff
                    r = r or ((x and 0x7f).toLong() shl s)
                    if (x and 0x80 == 0) return r
                    s += 7
                }
            }
            while (p < data.size) {
                val tag = varint()
                val field = (tag ushr 3).toInt()
                when ((tag and 7).toInt()) {
                    0 -> out.getOrPut(field) { mutableListOf() }.add(varint())
                    2 -> {
                        val n = varint().toInt()
                        out.getOrPut(field) { mutableListOf() }.add(data.copyOfRange(p, p + n))
                        p += n
                    }
                    1 -> p += 8
                    5 -> p += 4
                    else -> return out
                }
            }
            return out
        }
    }
}
