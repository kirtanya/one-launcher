package com.kirtanya.one_launcher.keyboard

/**
 * The keyboard's keys and D-pad movement, no Android types.
 *
 * Alphabetical square grid (not QWERTY): on a remote every letter costs its distance in presses, and
 * an alphabetical grid is both short to cross and instant to scan (you know where "t" is without
 * looking). Letters wrap left ↔ right so the far column is one press away. The action column sits on
 * the right of every row, so Delete / Space / Done are at most a few presses from any letter.
 */
sealed interface Key {
    data class Text(val text: String) : Key
    data object Delete : Key
    data object Space : Key
    data object Shift : Key
    data object Mode : Key
    data object Done : Key
}

enum class Mode { LETTERS, SYMBOLS }

object KeyGrid {
    const val COLS = 7
    const val ROWS = 5

    private val letters = listOf(
        "abcdef", "ghijkl", "mnopqr", "stuvwx", "yz'-.,",
    )
    private val symbols = listOf(
        "123456", "7890@#", "&_/:?!", "+=()*%", "$\";~<>",
    )
    private val actions = listOf(Key.Delete, Key.Space, Key.Shift, Key.Mode, Key.Done)

    fun key(mode: Mode, row: Int, col: Int): Key =
        if (col == COLS - 1) actions[row]
        else Key.Text((if (mode == Mode.LETTERS) letters else symbols)[row][col].toString())

    /** Where the focus starts when the keyboard opens: "a" (top left), the first thing people look for. */
    val START = Pos(0, 0)

    /**
     * A D-pad press from [p]. Row -1 is the suggestion strip ([chips] of them; 0 = none, then Up from the
     * top row does nothing). Left / Right wrap inside a row; Up / Down stop at the edges. Leaving the strip
     * downwards lands on the key under the chip's share of the width.
     */
    fun move(p: Pos, dir: Dir, chips: Int): Pos = when {
        p.row < 0 -> when (dir) {
            Dir.LEFT -> if (chips == 0) p else p.copy(col = (p.col - 1 + chips) % chips)
            Dir.RIGHT -> if (chips == 0) p else p.copy(col = (p.col + 1) % chips)
            Dir.DOWN -> Pos(0, if (chips == 0) 0 else (p.col * COLS / chips).coerceIn(0, COLS - 1))
            Dir.UP -> p
        }
        else -> when (dir) {
            Dir.LEFT -> p.copy(col = (p.col - 1 + COLS) % COLS)
            Dir.RIGHT -> p.copy(col = (p.col + 1) % COLS)
            Dir.DOWN -> if (p.row < ROWS - 1) p.copy(row = p.row + 1) else p
            Dir.UP -> when {
                p.row > 0 -> p.copy(row = p.row - 1)
                chips > 0 -> Pos(-1, (p.col * chips / COLS).coerceIn(0, chips - 1))
                else -> p
            }
        }
    }
}

data class Pos(val row: Int, val col: Int)

enum class Dir { UP, DOWN, LEFT, RIGHT }
