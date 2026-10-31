package com.kirtanya.one_launcher.keyboard

/**
 * Suggestions for what's typed so far, no Android types. On a remote a suggestion saves a dozen
 * presses per word, more than any layout can, so the strip leads with what this TV is likely to want:
 * what was typed here before, then One Stream titles and app names, then One Stream's own search.
 *
 * Matching is case-insensitive on the whole typed text (a TV field holds one query), as a prefix of
 * the candidate or of any word in it ("bad" finds "Breaking Bad").
 */
object Suggest {
    const val MAX = 5

    fun matches(typed: String, candidate: String): Boolean {
        val q = typed.trim().lowercase()
        if (q.isEmpty()) return false
        val c = candidate.lowercase()
        if (c == q) return false // already typed: nothing to save
        return c.startsWith(q) || c.split(' ', '-', ':', '.').any { it.startsWith(q) }
    }

    /** Sources in order of trust; duplicates (ignoring case) keep their first place. */
    fun rank(typed: String, vararg sources: List<String>): List<String> {
        val seen = HashSet<String>()
        val out = ArrayList<String>(MAX)
        for (source in sources) for (c in source) {
            if (out.size == MAX) return out
            if (matches(typed, c) && seen.add(c.lowercase())) out += c
        }
        return out
    }

    /** History after using [text]: newest first, no duplicates, capped. Blank text changes nothing. */
    fun remember(history: List<String>, text: String, cap: Int = 200): List<String> {
        val t = text.trim()
        if (t.isEmpty()) return history
        return (listOf(t) + history.filterNot { it.equals(t, ignoreCase = true) }).take(cap)
    }
}
