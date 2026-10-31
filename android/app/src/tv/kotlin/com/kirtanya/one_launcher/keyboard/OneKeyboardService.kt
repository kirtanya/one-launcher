package com.kirtanya.one_launcher.keyboard

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.inputmethodservice.InputMethodService
import android.inputmethodservice.InputMethodService.Insets
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import com.kirtanya.one_launcher.OneStream
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * One Launcher's system keyboard for the TV (Settings → System → Keyboard). Runs in its own process
 * (":keyboard", see the TV manifest): every app that opens a text field binds it, and that must not
 * start the launcher's Flutter engine, nor die with it.
 *
 * The remote's keys reach a shown keyboard before the app, so D-pad / OK drive the grid here and are
 * consumed; Back is left to the system (it closes the keyboard).
 */
class OneKeyboardService : InputMethodService() {
    private lateinit var view: KeyboardView
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val oneStream by lazy { OneStream(this) }
    private val prefs by lazy { getSharedPreferences("keyboard", MODE_PRIVATE) }

    private var secret = false // password fields: no suggestions, no history, no network
    private var multiLine = false
    private var action = EditorInfo.IME_ACTION_NONE

    // Local candidates, loaded off the main thread; refreshed at most every LOCAL_TTL_MS.
    @Volatile private var titles: List<String> = emptyList() // One Stream continue + My list
    @Volatile private var apps: List<String> = emptyList()
    @Volatile private var popular: List<String> = emptyList() // Cinemeta's top films + shows, daily
    private var localAt = 0L
    // One Stream search for [remoteFor] (stale answers are dropped).
    private var remote: List<String> = emptyList()
    private var remoteFor = ""
    private val search = Runnable { searchOneStream() }

    /**
     * The panel sits on the screen's bottom edge, right side (inside the TV safe area), only as big as its
     * keys; the rest of the keyboard window is clear. Search fields and first results sit top-left.
     */
    override fun onCreateInputView(): View {
        window.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        view = KeyboardView(this)
        return FrameLayout(this).apply {
            addView(view, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.BOTTOM or Gravity.END))
        }
    }

    // Tell the app nothing is covered, so it keeps its full screen (no squeezing its results into the
    // top half); the panel just sits over one corner. The TV has no touch, so nothing to hit-test.
    override fun onComputeInsets(outInsets: Insets) {
        super.onComputeInsets(outInsets)
        val h = window.window?.decorView?.height ?: return
        outInsets.contentTopInsets = h
        outInsets.visibleTopInsets = h
        outInsets.touchableInsets = Insets.TOUCHABLE_INSETS_VISIBLE
    }

    // The TV reports the remote as a keyboard; without this Android would hide the soft keyboard.
    override fun onEvaluateInputViewShown(): Boolean = true

    // Full-screen "extract" mode would cover the app; the TV has room for both.
    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val cls = info.inputType and InputType.TYPE_MASK_CLASS
        val variation = info.inputType and InputType.TYPE_MASK_VARIATION
        secret = cls == InputType.TYPE_CLASS_TEXT && variation in PASSWORDS ||
            cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        multiLine = info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        action = if (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) EditorInfo.IME_ACTION_NONE
        else info.imeOptions and EditorInfo.IME_MASK_ACTION
        if (!restarting) {
            view.mode = if (cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE) Mode.SYMBOLS else Mode.LETTERS
            view.shift = false
            view.pos = KeyGrid.START
        }
        view.doneLabel = when (action) {
            EditorInfo.IME_ACTION_SEARCH -> "Search"
            EditorInfo.IME_ACTION_GO -> "Go"
            EditorInfo.IME_ACTION_SEND -> "Send"
            EditorInfo.IME_ACTION_NEXT -> "Next"
            else -> if (multiLine) "New line" else "Done"
        }
        remote = emptyList()
        remoteFor = ""
        if (!secret) loadLocal()
        refresh()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        main.removeCallbacks(search)
        super.onFinishInputView(finishingInput)
    }

    // The app changed the text itself (cleared the field, moved the cursor): follow it.
    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        if (::view.isInitialized && isInputViewShown) refresh()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (!isInputViewShown) return super.onKeyDown(keyCode, event)
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> move(Dir.UP)
            KeyEvent.KEYCODE_DPAD_DOWN -> move(Dir.DOWN)
            KeyEvent.KEYCODE_DPAD_LEFT -> move(Dir.LEFT)
            KeyEvent.KEYCODE_DPAD_RIGHT -> move(Dir.RIGHT)
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                // Holding OK repeats only Delete (clearing a field); other keys type once per press.
                val onDelete = view.pos.row >= 0 && KeyGrid.key(view.mode, view.pos.row, view.pos.col) == Key.Delete
                if (event.repeatCount == 0 || onDelete) pressFocused()
            }
            KeyEvent.KEYCODE_DEL -> delete()
            in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> type(('0' + (keyCode - KeyEvent.KEYCODE_0)).toString())
            else -> return super.onKeyDown(keyCode, event)
        }
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (isInputViewShown && keyCode in HANDLED) return true
        return super.onKeyUp(keyCode, event)
    }

    private fun move(dir: Dir) {
        view.pos = KeyGrid.move(view.pos, dir, view.visibleChips)
        view.invalidate()
    }

    private fun pressFocused() {
        val p = view.pos
        if (p.row < 0) {
            view.chips.getOrNull(p.col)?.let(::pick)
            return
        }
        when (val key = KeyGrid.key(view.mode, p.row, p.col)) {
            is Key.Text -> {
                type(if (view.shift) key.text.uppercase() else key.text)
                view.shift = false // one capital, like a phone's single Shift tap
            }
            Key.Delete -> delete()
            Key.Space -> type(" ")
            Key.Shift -> if (view.mode == Mode.LETTERS) view.shift = !view.shift
            Key.Mode -> view.mode = if (view.mode == Mode.LETTERS) Mode.SYMBOLS else Mode.LETTERS
            Key.Done -> done()
        }
        view.invalidate()
    }

    private fun type(text: String) {
        currentInputConnection?.commitText(text, 1)
        refresh()
    }

    private fun delete() {
        val ic = currentInputConnection ?: return
        if (ic.getSelectedText(0).isNullOrEmpty()) ic.deleteSurroundingText(1, 0) else ic.commitText("", 1)
        refresh()
    }

    /** A suggestion replaces the whole query typed so far (a TV field holds one query). */
    private fun pick(text: String) {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.length ?: 0
        ic.beginBatchEdit()
        ic.deleteSurroundingText(before, 0)
        ic.commitText(text, 1)
        ic.endBatchEdit()
        learn(text)
        view.pos = KeyGrid.START
        refresh()
    }

    private fun done() {
        val ic = currentInputConnection ?: return
        learn(ic.getTextBeforeCursor(MAX_FIELD, 0)?.toString().orEmpty())
        when {
            action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED -> ic.performEditorAction(action)
            multiLine -> ic.commitText("\n", 1)
            else -> {
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
            }
        }
        if (!multiLine) requestHideSelf(0)
    }

    private fun learn(text: String) {
        if (secret) return
        val history = Suggest.remember(history(), text)
        prefs.edit().putString(HISTORY, history.joinToString("\n")).apply()
    }

    private fun history(): List<String> =
        prefs.getString(HISTORY, null)?.split('\n')?.filter { it.isNotBlank() }.orEmpty()

    /** Reads the field, redraws, and asks One Stream (debounced) once 3+ letters are typed. */
    private fun refresh() {
        val typed = currentInputConnection?.getTextBeforeCursor(MAX_FIELD, 0)?.toString().orEmpty()
        view.typed = if (secret) "•".repeat(typed.length) else typed
        if (secret) {
            view.chips = emptyList()
            view.hints = emptyList()
        } else {
            // Films first: this keyboard is mostly for finding something to watch. What's popular now
            // beats TMDB's search order, which ranks the closest text first ("joke": Joke Book before Joker).
            val sources = listOf(
                history(), titles, popular, if (remoteFor.equals(typed.trim(), true)) remote else emptyList(), apps,
            )
            view.chips = Suggest.rank(typed, *sources.toTypedArray())
            view.hints = Suggest.nextKeys(typed, sources)
            main.removeCallbacks(search)
            if (typed.trim().length >= SEARCH_FROM && !remoteFor.equals(typed.trim(), true)) main.postDelayed(search, SEARCH_DELAY_MS)
        }
        if (view.pos.row < 0 && view.pos.col >= view.chips.size) view.pos = KeyGrid.START
        view.invalidate()
    }

    private fun searchOneStream() {
        val q = currentInputConnection?.getTextBeforeCursor(MAX_FIELD, 0)?.toString()?.trim().orEmpty()
        if (q.length < SEARCH_FROM) return
        worker.execute {
            val titles = runCatching { oneStream.query("/search", mapOf("q" to q, "limit" to "8")) }.getOrDefault(emptyList())
                .mapNotNull { it["title"] as? String }
            main.post {
                remote = titles
                remoteFor = q
                if (isInputViewShown) refresh()
            }
        }
    }

    /**
     * One Stream's Continue watching + My list titles and the TV's app names (cached a few minutes), and
     * the popular list (kept in prefs, fetched again once a day).
     */
    private fun loadLocal() {
        val now = SystemClock.elapsedRealtime()
        if (localAt != 0L && now - localAt < LOCAL_TTL_MS) return
        localAt = now
        worker.execute {
            titles = runCatching {
                (oneStream.query("/continue", mapOf("limit" to "20")) + oneStream.query("/watchlist", mapOf("limit" to "40")))
                    .mapNotNull { it["title"] as? String }
            }.getOrDefault(emptyList())
            apps = runCatching {
                packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER), 0)
                    .map { it.loadLabel(packageManager).toString() }
            }.getOrDefault(emptyList())
            popular = prefs.getString(POPULAR, null)?.split('\n')?.filter { it.isNotBlank() }.orEmpty()
            main.post { if (isInputViewShown) refresh() }
            if (System.currentTimeMillis() - prefs.getLong(POPULAR_AT, 0) > POPULAR_TTL_MS) fetchPopular()
        }
    }

    /**
     * Cinemeta's "top" (what's popular now), films then shows, ~50 a page. Public and keyless, the same
     * catalog the TV search uses. Nothing about the user is sent. Runs on [worker].
     */
    private fun fetchPopular() {
        val pages = (0 until 500 step 50).map { "movie" to it } + (0 until 200 step 50).map { "series" to it }
        val names = LinkedHashSet<String>()
        for ((type, skip) in pages) {
            val url = "https://v3-cinemeta.strem.io/catalog/$type/top" + (if (skip > 0) "/skip=$skip" else "") + ".json"
            runCatching {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 8_000
                c.readTimeout = 8_000
                try {
                    val metas = JSONObject(c.inputStream.bufferedReader().readText()).getJSONArray("metas")
                    for (i in 0 until metas.length()) metas.getJSONObject(i).optString("name").trim().takeIf { it.isNotEmpty() }?.let(names::add)
                } finally {
                    c.disconnect()
                }
            }
        }
        if (names.size < 50) return // offline or Cinemeta changed: keep yesterday's list
        popular = names.toList()
        prefs.edit().putString(POPULAR, popular.joinToString("\n")).putLong(POPULAR_AT, System.currentTimeMillis()).apply()
        main.post { if (isInputViewShown) refresh() }
    }

    companion object {
        private const val HISTORY = "history"
        private const val POPULAR = "popular"
        private const val POPULAR_AT = "popular_at"
        private const val POPULAR_TTL_MS = 24 * 60 * 60_000L
        private const val SEARCH_FROM = 2 // letters before One Stream's search is asked
        private const val MAX_FIELD = 500
        private const val SEARCH_DELAY_MS = 300L
        private const val LOCAL_TTL_MS = 5 * 60_000L
        private val PASSWORDS = setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )
        private val HANDLED = setOf(
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DEL,
        ) + (KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9)
    }
}
