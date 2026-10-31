package com.kirtanya.one_launcher.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.text.TextUtils
import android.view.View

/**
 * Draws the keyboard with plain Canvas calls: no Flutter engine in the keyboard process (it would cost
 * tens of MB and a slow first show on the 32-bit TV), no child views, nothing animating. Colours follow
 * the TV launcher (`TvDS`): dark panel, faint keys, focus = white fill (focus never scales).
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context) : View(context) {
    var mode = Mode.LETTERS
    var shift = false
    var pos = KeyGrid.START
    var chips: List<String> = emptyList()
    /** What's typed so far, shown when there are no suggestions (some apps hide their field). */
    var typed = ""
    var doneLabel = "Done"

    /** How many chips fit on one line (D-pad moves only between these). */
    var visibleChips = 0
        private set

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    private val keyW = dp(56f)
    private val actionW = dp(104f)
    private val keyH = dp(38f)
    private val gap = dp(6f)
    private val stripH = dp(36f)
    private val padTop = dp(14f)
    private val padBottom = dp(18f)
    private val radius = dp(8f)
    private val gridW = (KeyGrid.COLS - 1) * keyW + (KeyGrid.COLS - 1) * gap + actionW
    private val chipMaxW = dp(240f)
    private val chipPad = dp(14f)

    private val panel = Paint().apply { color = 0xFF1C1C1C.toInt() }
    private val keyFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x14FFFFFF }
    private val keyOn = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x40FFFFFF } // Shift held
    private val focusFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt() }
    private val letter = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(19f); textAlign = Paint.Align.CENTER }
    private val label = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(14f); textAlign = Paint.Align.CENTER }
    private val chipText = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(15f) }
    private val hint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(15f); color = 0x99FFFFFF.toInt() }
    private val ink = 0xE6FFFFFF.toInt()
    private val inkOnFocus = 0xFF161616.toInt()
    private val rect = RectF()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val h = padTop + stripH + gap + KeyGrid.ROWS * keyH + (KeyGrid.ROWS - 1) * gap + padBottom
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), h.toInt())
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), panel)
        val left = (width - gridW) / 2
        drawStrip(canvas, left, padTop)
        val top = padTop + stripH + gap
        for (row in 0 until KeyGrid.ROWS) for (col in 0 until KeyGrid.COLS) {
            val x = left + col * (keyW + gap)
            val y = top + row * (keyH + gap)
            rect.set(x, y, x + if (col == KeyGrid.COLS - 1) actionW else keyW, y + keyH)
            val key = KeyGrid.key(mode, row, col)
            val focused = pos.row == row && pos.col == col
            canvas.drawRoundRect(rect, radius, radius, if (focused) focusFill else if (key == Key.Shift && shift) keyOn else keyFill)
            val p = if (key is Key.Text) letter else label
            p.color = if (focused) inkOnFocus else ink
            canvas.drawText(text(key), rect.centerX(), rect.centerY() - (p.descent() + p.ascent()) / 2, p)
        }
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
            val line = typed.ifEmpty { "Type with the arrows and OK · Back closes" }
            val shown = TextUtils.ellipsize(line, hint, gridW, TextUtils.TruncateAt.START).toString()
            hint.color = if (typed.isEmpty()) 0x99FFFFFF.toInt() else ink
            canvas.drawText(shown, left, top + stripH / 2 - (hint.descent() + hint.ascent()) / 2, hint)
        }
    }

    private fun text(key: Key): String = when (key) {
        is Key.Text -> if (shift) key.text.uppercase() else key.text
        Key.Delete -> "Delete"
        Key.Space -> "Space"
        Key.Shift -> if (mode == Mode.SYMBOLS) "" else "Shift"
        Key.Mode -> if (mode == Mode.LETTERS) "123" else "abc"
        Key.Done -> doneLabel
    }
}
