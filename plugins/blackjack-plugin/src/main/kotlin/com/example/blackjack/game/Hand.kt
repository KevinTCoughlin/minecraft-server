package com.example.blackjack.game

/**
 * Represents a hand of cards in a Blackjack game.
 *
 * A hand tracks the cards held by a player or dealer and provides
 * calculations for hand value, including proper handling of Aces
 * (counted as 11 or 1 to avoid busting).
 */
class Hand(
    val isFromSplit: Boolean = false,
    val isSplitAces: Boolean = false
) {
    private val _cards = mutableListOf<Card>()

    /** An immutable view of the cards currently in this hand. */
    val cards: List<Card> get() = _cards.toList()

    /** The number of cards in this hand. */
    val size: Int get() = _cards.size

    /** Whether this hand has doubled down. */
    var hasDoubledDown: Boolean = false
        private set

    /** Whether this hand has surrendered. */
    var hasSurrendered: Boolean = false
        private set

    /**
     * The optimal value of this hand.
     *
     * Aces are initially counted as 11, but are converted to 1
     * as needed to keep the total at or below 21.
     */
    val value: Int get() {
        val total = _cards.sumOf { it.value }
        val aceCount = _cards.count { it.rank == Rank.ACE }

        return (0 until aceCount).fold(total) { acc, _ ->
            if (acc > 21) acc - 10 else acc
        }
    }

    /**
     * Returns `true` if this hand is "soft" (contains an Ace counted as 11).
     * A soft hand can safely take another card without risk of immediate bust.
     */
    val isSoft: Boolean get() {
        val total = _cards.sumOf { it.value }
        val aceCount = _cards.count { it.rank == Rank.ACE }

        // Count how many aces we need to convert to avoid bust
        var adjustedTotal = total
        var remainingAces = aceCount
        while (adjustedTotal > 21 && remainingAces > 0) {
            adjustedTotal -= 10
            remainingAces--
        }

        // Hand is soft if we still have at least one ace counted as 11
        return remainingAces > 0 && adjustedTotal <= 21
    }

    /** Returns `true` if the hand value exceeds 21. */
    val isBust: Boolean get() = value > 21

    /** Returns `true` if this is a natural Blackjack (two cards totaling 21, not from split). */
    val isBlackjack: Boolean get() = size == 2 && value == 21 && !isFromSplit

    /** Returns `true` if this hand is a pair (two cards of the same rank). */
    val isPair: Boolean get() = size == 2 && _cards[0].rank == _cards[1].rank

    /** Returns `true` if this hand can be split (is a pair and not already from a split). */
    fun canSplit(maxSplitHands: Int, currentHandCount: Int): Boolean {
        return isPair && currentHandCount < maxSplitHands &&
               (!isFromSplit || !isSplitAces) // Can't re-split aces unless allowed
    }

    /** Returns `true` if this hand can double down based on the given rule. */
    fun canDoubleDown(rule: DoubleDownRule, allowDoubleAfterSplit: Boolean): Boolean {
        if (size != 2 || hasDoubledDown) return false
        if (isFromSplit && !allowDoubleAfterSplit) return false

        return when (rule) {
            DoubleDownRule.ANY_TWO_CARDS -> true
            DoubleDownRule.NINE_TEN_ELEVEN -> value in 9..11
            DoubleDownRule.TEN_ELEVEN -> value in 10..11
            DoubleDownRule.ELEVEN_ONLY -> value == 11
        }
    }

    /** Mark this hand as having doubled down. */
    fun markDoubledDown() {
        hasDoubledDown = true
    }

    /** Mark this hand as having surrendered. */
    fun markSurrendered() {
        hasSurrendered = true
    }

    /**
     * Adds a card to this hand using the `+=` operator.
     *
     * @param card the card to add
     */
    operator fun plusAssign(card: Card) {
        _cards += card
    }

    /**
     * Adds a card to this hand.
     *
     * @param card the card to add
     */
    fun addCard(card: Card) {
        _cards += card
    }

    /** Gets the first card in this hand, or null if empty. */
    fun getFirstCard(): Card? = _cards.getOrNull(0)

    /** Removes and returns the last card from this hand, or null if empty. */
    fun removeLastCard(): Card? {
        return if (_cards.isNotEmpty()) {
            _cards.removeAt(_cards.lastIndex)
        } else null
    }

    /** Removes all cards from this hand and resets state. */
    fun clear() {
        _cards.clear()
        hasDoubledDown = false
        hasSurrendered = false
    }
}
