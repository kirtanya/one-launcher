package com.kirtanya.one_launcher.keyboard

/**
 * Suggestions for what's typed so far, no Android types. On a remote a suggestion saves a dozen
 * presses per word, more than any layout can, so the strip leads with what this TV is likely to want:
 * what was typed here before, then One Stream titles and app names, then One Stream's own search.
 *
 * Matching is case-insensitive on the whole typed text (a TV field holds one query), as a prefix of
 * the candidate or of any word in it ("bad" finds "Breaking Bad"). Better matches lead whatever their
 * source: the exact title ("joker" → Joker), then titles that start with it (Joker: Folie à Deux),
 * then titles with a word that does (Batman: The Killing Joke).
 */
object Suggest {
    const val MAX = 5

    /** 0 = the exact title, 1 = starts with it, 2 = a word starts with it, null = no match. */
    fun match(typed: String, candidate: String): Int? {
        val q = typed.trim().lowercase()
        if (q.isEmpty()) return null
        val c = candidate.trim().lowercase()
        return when {
            c == q -> 0 // still worth showing: picking it confirms the title and learns it
            c.startsWith(q) -> 1
            c.split(' ', '-', ':', '.').any { it.startsWith(q) } -> 2
            else -> null
        }
    }

    /**
     * Best match first; within a match, sources in order of trust, then each source's own order (One
     * Stream's search is by popularity). Duplicates (ignoring case) keep their best place.
     */
    fun rank(typed: String, vararg sources: List<String>): List<String> {
        val found = ArrayList<Pair<Int, String>>()
        for (source in sources) for (c in source) match(typed, c)?.let { found += it to c }
        val seen = HashSet<String>()
        return found.sortedBy { it.first } // stable: source and position order hold within a match
            .map { it.second }
            .filter { seen.add(it.trim().lowercase()) }
            .take(MAX)
    }

    /**
     * The [n] characters most likely typed next, read from where each matching candidate continues
     * (earlier candidates weigh more): typed "a" with Avatar, Avengers, Animal → v, n. ' ' = Space.
     */
    fun nextKeys(typed: String, sources: List<List<String>>, n: Int = 3): List<Char> {
        val q = typed.trimStart().lowercase()
        if (q.isBlank()) return emptyList()
        val weight = HashMap<Char, Double>()
        var seen = 0
        for (source in sources) for (c in source) {
            if (seen == HINT_POOL) break
            val t = c.lowercase()
            val at = if (t.startsWith(q)) q.length
            else WORD.findAll(t).firstOrNull { t.startsWith(q, it.range.first) }?.let { it.range.first + q.length }
            val next = at?.let { t.getOrNull(it) } ?: continue
            weight[next] = (weight[next] ?: 0.0) + 1.0 / (1 + seen++)
        }
        return weight.entries.sortedByDescending { it.value }.take(n).map { it.key }
    }

    private const val HINT_POOL = 40
    private val WORD = Regex("""(?<=[ \-:.])\S""")

    /** History after using [text]: newest first, no duplicates, capped. Blank text changes nothing. */
    fun remember(history: List<String>, text: String, cap: Int = 200): List<String> {
        val t = text.trim()
        if (t.isEmpty()) return history
        return (listOf(t) + history.filterNot { it.equals(t, ignoreCase = true) }).take(cap)
    }
}
