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
    const val GRACE_MS = 5000L

    @Volatile var locked: Set<String> = emptySet()
        private set

    private class Allowance(val at: Long, var seen: Boolean = false)
    private val allowed = HashMap<String, Allowance>()
    @Volatile private var loaded = false

    fun load(ctx: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            locked = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(KEY, emptySet())?.toSet() ?: emptySet()
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

    fun allow(pkg: String) = synchronized(allowed) {
        allowed[pkg] = Allowance(SystemClock.elapsedRealtime())
    }

    /** True while [pkg] may be in the foreground: it appeared already, or is still within the grace. */
    fun isAllowed(pkg: String): Boolean = synchronized(allowed) {
        val a = allowed[pkg] ?: return false
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
            if (e.value.seen || now - e.value.at > GRACE_MS) it.remove()
        }
    }
}
