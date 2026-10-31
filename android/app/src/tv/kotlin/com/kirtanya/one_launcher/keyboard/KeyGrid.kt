package com.kirtanya.one_launcher.keyboard

/**
 * The keyboard's keys and D-pad movement, no Android types.
 *
 * Alphabetical square grid (not QWERTY): on a remote every letter costs its distance in presses, and
 * an alphabetical grid is both short to cross and instant to scan (you know where "t" is without
 * looking). Letters wrap left ↔ right so the far column is one press away. The right column is two
 * tall keys, Delete over the top two rows and Space over the bottom three, so Left / Right off either
 * end of a row reaches one in a press. Done (Search / Go …) is its own full-width row underneath.
 */
sealed interface Key {
    data class Text(val text: String) : Key
    data object Delete : Key
    data object Space : Key
    data object Mode : Key
    data object Done : Key
}

enum class Mode { LETTERS, SYMBOLS }

object KeyGrid {
    const val COLS = 7
    /** Key rows; the Done bar is the row after them. */
    const val GRID = 5
    const val DONE_ROW = GRID
    const val ROWS = GRID + 1

    private val letters = listOf(
        "abcdef", "ghijkl", "mnopqr", "stuvwx", "yz-.,",
    )
    private val symbols = listOf(
        "123456", "7890@#", "&_/:?!", "+=()*%", "$\"<>;",
    )
    /** The key rows the right column's two tall keys cover. */
    val DELETE_ROWS = 0..1
    val SPACE_ROWS = 2 until GRID

    /** 123 / abc sits at the end of the bottom key row, after the punctuation. */
    fun key(mode: Mode, row: Int, col: Int): Key {
        if (row == DONE_ROW) return Key.Done
        if (col == COLS - 1) return if (row in DELETE_ROWS) Key.Delete else Key.Space
        val line = (if (mode == Mode.LETTERS) letters else symbols)[row]
        return if (col < line.length) Key.Text(line[col].toString()) else Key.Mode
    }

    /** Where the focus starts when the keyboard opens: "o", mid-grid, so any letter is a few presses away. */
    val START = Pos(2, 2)

    /**
     * A D-pad press from [p]. Row -1 is the suggestion strip ([chips] of them; 0 = no strip). Everything
     * wraps: Left / Right inside a row, Up / Down round the column (strip → top row … bottom row → strip,
     * skipping the strip when it's empty). Entering or leaving the strip keeps the share of the width.
     * Up / Down on a tall key jump past its rows; Left / Right off it go back along the row the focus
     * came in on. The Done bar keeps the column it was entered from, so Up returns there.
     */
    fun move(p: Pos, dir: Dir, chips: Int): Pos = when {
        p.row < 0 -> when (dir) {
            Dir.LEFT -> if (chips == 0) p else p.copy(col = (p.col - 1 + chips) % chips)
            Dir.RIGHT -> if (chips == 0) p else p.copy(col = (p.col + 1) % chips)
            Dir.DOWN -> Pos(0, keyUnder(p.col, chips))
            Dir.UP -> Pos(DONE_ROW, keyUnder(p.col, chips))
        }
        p.row == DONE_ROW -> when (dir) {
            Dir.UP -> p.copy(row = GRID - 1)
            Dir.DOWN -> stripOver(p.col, chips) ?: p.copy(row = 0)
            else -> p
        }
        else -> when (dir) {
            Dir.LEFT -> p.copy(col = (p.col - 1 + COLS) % COLS)
            Dir.RIGHT -> p.copy(col = (p.col + 1) % COLS)
            Dir.DOWN -> when {
                p.col == COLS - 1 && p.row in DELETE_ROWS -> p.copy(row = SPACE_ROWS.first)
                p.col == COLS - 1 || p.row == GRID - 1 -> p.copy(row = DONE_ROW)
                else -> p.copy(row = p.row + 1)
            }
            Dir.UP -> when {
                p.col == COLS - 1 && p.row in SPACE_ROWS -> p.copy(row = DELETE_ROWS.last)
                p.col == COLS - 1 || p.row == 0 -> stripOver(p.col, chips) ?: p.copy(row = DONE_ROW)
                else -> p.copy(row = p.row - 1)
            }
        }
    }

    private fun stripOver(col: Int, chips: Int) = if (chips > 0) Pos(-1, chipOver(col, chips)) else null

    private fun keyUnder(chip: Int, chips: Int) = if (chips == 0) 0 else (chip * COLS / chips).coerceIn(0, COLS - 1)
    private fun chipOver(col: Int, chips: Int) = (col * chips / COLS).coerceIn(0, chips - 1)
}

data class Pos(val row: Int, val col: Int)

enum class Dir { UP, DOWN, LEFT, RIGHT }
