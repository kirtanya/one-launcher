package com.kirtanya.one_launcher

import android.content.Context
import android.os.SystemClock

/**
 * State for "App lock": the locked package set (persisted in its own prefs file so it works with
 * Flutter not running) and the short-lived allowances Dart grants just before launching a locked
 * app. Read by [LockService]; written by MainActivity's method channel.
 */
object AppLockGuard {
    private const val PREFS = "app_lock"
    private const val KEY = "packages"
    private const val GRACE_KEY = "graceMs"
    const val GRACE_MS = 5000L

    @Volatile var locked: Set<String> = emptySet()
        private set

    /** "Reopen without lock": an app the user left (after opening it properly) reopens anywhere within this. 0 = off. */
    @Volatile var graceMs = 0L
        private set

    private class Allowance(val at: Long, var seen: Boolean = false)
    private val allowed = HashMap<String, Allowance>()
    private val left = HashMap<String, Long>() // allowed app → when the user left it
    @Volatile private var loaded = false

    fun load(ctx: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            val sp = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            locked = sp.getStringSet(KEY, emptySet())?.toSet() ?: emptySet()
            graceMs = sp.getLong(GRACE_KEY, 0L)
            loaded = true
        }
    }

    fun setLocked(ctx: Context, packages: List<String>) {
        val set = packages.toSet()
        synchronized(this) {
            locked = set
            loaded = true
            allowed.keys.retainAll(set)
        }
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY, set).apply()
        LockService.sync(ctx) // start / stop the watcher
    }

    fun setGrace(ctx: Context, seconds: Int) {
        graceMs = seconds.coerceIn(0, 60) * 1000L
        synchronized(allowed) { if (graceMs == 0L) left.clear() }
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong(GRACE_KEY, graceMs).apply()
    }

    /** True when [pkg] was left (after a proper open) less than [graceMs] ago. */
    fun recentlyLeft(pkg: String): Boolean = synchronized(allowed) {
        val at = left[pkg] ?: return false
        if (SystemClock.elapsedRealtime() - at <= graceMs) return true
        left.remove(pkg)
        false
    }

    fun allow(pkg: String) = synchronized(allowed) {
        allowed[pkg] = Allowance(SystemClock.elapsedRealtime())
    }

    /** True while [pkg] may be in the foreground: it appeared already, or is still within the grace. */
    fun isAllowed(pkg: String): Boolean = synchronized(allowed) {
        val a = allowed[pkg] ?: run {
            if (!recentlyLeft(pkg)) return false
            left.remove(pkg) // reopened within the grace: allowed again until it's left again
            allowed[pkg] = Allowance(SystemClock.elapsedRealtime(), seen = true)
            return true
        }
        if (a.seen) return true
        if (SystemClock.elapsedRealtime() - a.at <= GRACE_MS) { a.seen = true; return true }
        allowed.remove(pkg)
        false
    }

    /** The user moved to another app / our launcher: end allowances of apps that already appeared. */
    fun endAllowancesExcept(pkg: String?) = synchronized(allowed) {
        val it = allowed.entries.iterator()
        val now = SystemClock.elapsedRealtime()
        while (it.hasNext()) {
            val e = it.next()
            if (e.key == pkg) continue
            if (e.value.seen || now - e.value.at > GRACE_MS) {
                if (e.value.seen && graceMs > 0) left[e.key] = now
                it.remove()
            }
        }
    }
}
