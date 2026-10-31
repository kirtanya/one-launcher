package com.kirtanya.one_launcher.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.text.TextPaint
import android.text.TextUtils
import android.view.View

/**
 * Draws the keyboard with plain Canvas calls: no Flutter engine in the keyboard process (it would cost
 * tens of MB and a slow first show on the 32-bit TV), no child views, nothing animating. Colours follow
 * the TV launcher (`TvDS`): dark panel, faint keys, focus = white fill (focus never scales).
 *
 * The view is only as big as its keys: a rounded panel the service floats in a bottom corner, so the
 * app's own results stay in view around it. Action keys are drawn icons (Delete, Space, Shift, Done).
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context) : View(context) {
    var mode = Mode.LETTERS
    var shift = false
    var pos = KeyGrid.START
    var chips: List<String> = emptyList()
    /** What's typed so far, shown when there are no suggestions (some apps hide their field). */
    var typed = ""
    /** The app's action (Search / Go / Send / Next / New line / Done): picks the Done key's icon. */
    var doneLabel = "Done"

    /** How many chips fit on one line (D-pad moves only between these). */
    var visibleChips = 0
        private set

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    private val keyW = dp(52f)
    private val actionW = dp(72f)
    private val keyH = dp(42f)
    private val gap = dp(6f)
    private val stripH = dp(34f)
    private val pad = dp(16f)
    private val radius = dp(8f)
    private val panelRadius = dp(20f)
    private val gridW = (KeyGrid.COLS - 1) * keyW + (KeyGrid.COLS - 1) * gap + actionW
    private val chipMaxW = dp(200f)
    private val chipPad = dp(14f)
    private val icon = dp(11f) // half an icon's box

    private val panel = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF1C1C1C.toInt() }
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f); color = 0x1FFFFFFF }
    private val keyFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x14FFFFFF }
    private val keyOn = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x40FFFFFF } // Shift held
    private val focusFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt() }
    private val letter = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(19f); textAlign = Paint.Align.CENTER }
    private val label = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(15f); textAlign = Paint.Align.CENTER }
    private val chipText = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(15f) }
    private val hint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(15f) }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = dp(2f); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val ink = 0xE6FFFFFF.toInt()
    private val inkOnFocus = 0xFF161616.toInt()
    private val rect = RectF()
    private val path = Path()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val h = pad + stripH + gap + KeyGrid.ROWS * keyH + (KeyGrid.ROWS - 1) * gap + pad
        setMeasuredDimension((gridW + 2 * pad).toInt(), h.toInt())
    }

    override fun onDraw(canvas: Canvas) {
        rect.set(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawRoundRect(rect, panelRadius, panelRadius, panel)
        rect.inset(edge.strokeWidth / 2, edge.strokeWidth / 2)
        canvas.drawRoundRect(rect, panelRadius, panelRadius, edge)
        drawStrip(canvas, pad, pad)
        val top = pad + stripH + gap
        for (row in 0 until KeyGrid.ROWS) for (col in 0 until KeyGrid.COLS) {
            val x = pad + col * (keyW + gap)
            val y = top + row * (keyH + gap)
            rect.set(x, y, x + if (col == KeyGrid.COLS - 1) actionW else keyW, y + keyH)
            val key = KeyGrid.key(mode, row, col)
            val focused = pos.row == row && pos.col == col
            canvas.drawRoundRect(rect, radius, radius, if (focused) focusFill else if (key == Key.Shift && shift) keyOn else keyFill)
            drawKey(canvas, key, if (focused) inkOnFocus else ink)
        }
    }

    private fun drawKey(canvas: Canvas, key: Key, color: Int) {
        val cx = rect.centerX()
        val cy = rect.centerY()
        stroke.color = color
        stroke.style = Paint.Style.STROKE
        path.reset()
        when (key) {
            is Key.Text -> text(canvas, if (shift) key.text.uppercase() else key.text, letter, color)
            Key.Mode -> text(canvas, if (mode == Mode.LETTERS) "123" else "abc", label, color)
            Key.Delete -> { // ⌫
                val l = cx - icon * 1.15f; val r = cx + icon * 1.15f; val t = cy - icon * 0.75f; val b = cy + icon * 0.75f
                path.moveTo(l + icon * 0.6f, t); path.lineTo(r, t); path.lineTo(r, b); path.lineTo(l + icon * 0.6f, b); path.lineTo(l, cy); path.close()
                val x = cx + icon * 0.25f; val s = icon * 0.32f
                path.moveTo(x - s, cy - s); path.lineTo(x + s, cy + s); path.moveTo(x + s, cy - s); path.lineTo(x - s, cy + s)
            }
            Key.Space -> { // ␣
                val l = cx - icon * 1.2f; val r = cx + icon * 1.2f
                path.moveTo(l, cy - icon * 0.2f); path.lineTo(l, cy + icon * 0.35f); path.lineTo(r, cy + icon * 0.35f); path.lineTo(r, cy - icon * 0.2f)
            }
            Key.Shift -> { // ⇧, filled while on; nothing in symbols (no capitals there)
                if (mode == Mode.SYMBOLS) return
                val t = cy - icon; val b = cy + icon * 0.9f; val s = icon * 0.4f
                path.moveTo(cx, t); path.lineTo(cx + icon, cy); path.lineTo(cx + s, cy); path.lineTo(cx + s, b)
                path.lineTo(cx - s, b); path.lineTo(cx - s, cy); path.lineTo(cx - icon, cy); path.close()
                if (shift) stroke.style = Paint.Style.FILL_AND_STROKE
            }
            Key.Done -> when (doneLabel) {
                "Search" -> { // magnifier
                    val r = icon * 0.62f
                    path.addCircle(cx - icon * 0.2f, cy - icon * 0.2f, r, Path.Direction.CW)
                    path.moveTo(cx + icon * 0.25f, cy + icon * 0.25f); path.lineTo(cx + icon * 0.9f, cy + icon * 0.9f)
                }
                "Go", "Send", "Next" -> { // →
                    path.moveTo(cx - icon, cy); path.lineTo(cx + icon, cy)
                    path.moveTo(cx + icon * 0.4f, cy - icon * 0.6f); path.lineTo(cx + icon, cy); path.lineTo(cx + icon * 0.4f, cy + icon * 0.6f)
                }
                "New line" -> { // ↵
                    path.moveTo(cx + icon, cy - icon * 0.8f); path.lineTo(cx + icon, cy + icon * 0.2f); path.lineTo(cx - icon, cy + icon * 0.2f)
                    path.moveTo(cx - icon * 0.5f, cy - icon * 0.3f); path.lineTo(cx - icon, cy + icon * 0.2f); path.lineTo(cx - icon * 0.5f, cy + icon * 0.7f)
                }
                else -> { // ✓
                    path.moveTo(cx - icon, cy); path.lineTo(cx - icon * 0.3f, cy + icon * 0.7f); path.lineTo(cx + icon, cy - icon * 0.7f)
                }
            }
        }
        if (!path.isEmpty) canvas.drawPath(path, stroke)
    }

    private fun text(canvas: Canvas, s: String, p: TextPaint, color: Int) {
        p.color = color
        canvas.drawText(s, rect.centerX(), rect.centerY() - (p.descent() + p.ascent()) / 2, p)
    }

    private fun drawStrip(canvas: Canvas, left: Float, top: Float) {
        var x = left
        visibleChips = 0
        for ((i, chip) in chips.withIndex()) {
            val shown = TextUtils.ellipsize(chip, chipText, chipMaxW - 2 * chipPad, TextUtils.TruncateAt.END).toString()
            val w = chipText.measureText(shown) + 2 * chipPad
            if (x + w > left + gridW) break
            rect.set(x, top, x + w, top + stripH)
            val focused = pos.row == -1 && pos.col == i
            canvas.drawRoundRect(rect, stripH / 2, stripH / 2, if (focused) focusFill else keyFill)
            chipText.color = if (focused) inkOnFocus else ink
            canvas.drawText(shown, x + chipPad, rect.centerY() - (chipText.descent() + chipText.ascent()) / 2, chipText)
            x += w + gap
            visibleChips++
        }
        if (visibleChips == 0) {
            val line = typed.ifEmpty { "Arrows + OK to type · Back closes" }
            val shown = TextUtils.ellipsize(line, hint, gridW, TextUtils.TruncateAt.START).toString()
            hint.color = if (typed.isEmpty()) 0x99FFFFFF.toInt() else ink
            canvas.drawText(shown, left, top + stripH / 2 - (hint.descent() + hint.ascent()) / 2, hint)
        }
    }
}
