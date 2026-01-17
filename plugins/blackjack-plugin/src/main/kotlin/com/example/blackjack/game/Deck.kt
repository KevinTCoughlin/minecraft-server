package com.example.blackjack.game

/**
 * A multi-deck shoe for Blackjack.
 *
 * Supports configurable number of decks and automatic reshuffling
 * when penetration reaches the threshold.
 *
 * @property numberOfDecks Number of standard 52-card decks (1–8).
 * @property reshuffleThreshold Fraction of cards remaining that triggers reshuffle.
 */
class Deck(
    private val numberOfDecks: Int = 1,
    private val reshuffleThreshold: Double = 0.25
) {
    private val _cards = mutableListOf<Card>()
    private var _totalCards: Int = 0

    /** The number of cards remaining in the shoe. */
    val remaining: Int get() = _cards.size

    /** The total number of cards when the shoe is full. */
    val totalCardsInShoe: Int get() = _totalCards

    /** Returns `true` if the shoe has no cards remaining. */
    val isEmpty: Boolean get() = _cards.isEmpty()

    /**
     * The current penetration (fraction of shoe already dealt).
     *
     * Returns 0.0 for a fresh shoe, approaching 1.0 as cards are dealt.
     */
    val penetration: Double
        get() = if (_totalCards > 0) 1.0 - (_cards.size.toDouble() / _totalCards) else 0.0

    init {
        require(numberOfDecks in 1..8) { "Number of decks must be between 1 and 8" }
        reset()
    }

    /** Resets the shoe to full and shuffles all cards. */
    fun reset() {
        _cards.clear()
        repeat(numberOfDecks) {
            Suit.entries.forEach { suit ->
                Rank.entries.forEach { rank ->
                    _cards += Card(rank, suit)
                }
            }
        }
        _totalCards = _cards.size
        shuffle()
    }

    /** Shuffles the remaining cards in the shoe. */
    fun shuffle() {
        _cards.shuffle()
    }

    /**
     * Draws a card from the shoe.
     *
     * Automatically resets if empty or penetration threshold is reached.
     *
     * @return The drawn card.
     */
    fun draw(): Card {
        if (isEmpty || needsReshuffle()) reset()
        return _cards.removeLast()
    }

    /** Returns `true` if the shoe has reached the reshuffle threshold. */
    fun needsReshuffle(): Boolean =
        _cards.size <= (_totalCards * reshuffleThreshold).toInt()
}
