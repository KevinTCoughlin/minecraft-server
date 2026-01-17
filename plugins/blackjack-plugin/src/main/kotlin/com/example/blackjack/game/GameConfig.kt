package com.example.blackjack.game

/**
 * Configuration options for a Blackjack game.
 *
 * Provides sensible defaults matching standard casino rules.
 */
data class GameConfig(
    /** Number of decks to use (1–8). */
    val numberOfDecks: Int = 1,

    /** Reshuffle when this fraction of cards remain (0.1–0.5). */
    val reshuffleThreshold: Double = 0.25,

    /** Whether the dealer stands on soft 17. */
    val dealerStandsOnSoft17: Boolean = true,

    /** Whether the dealer peeks for Blackjack when showing Ace/10. */
    val dealerPeeks: Boolean = true,

    /** Whether players can double down. */
    val allowDoubleDown: Boolean = true,

    /** Restriction on when doubling down is allowed. */
    val doubleDownOn: DoubleDownRule = DoubleDownRule.ANY_TWO_CARDS,

    /** Whether players can double after splitting. */
    val allowDoubleAfterSplit: Boolean = true,

    /** Whether players can split pairs. */
    val allowSplit: Boolean = true,

    /** Maximum number of hands from splitting (2–4). */
    val maxSplitHands: Int = 4,

    /** Whether players can re-split Aces. */
    val allowResplitAces: Boolean = false,

    /** Whether players can hit after splitting Aces. */
    val allowHitSplitAces: Boolean = false,

    /** Whether surrender is allowed. */
    val allowSurrender: Boolean = true,

    /** The type of surrender allowed. */
    val surrenderType: SurrenderType = SurrenderType.LATE,

    /** Whether insurance bets are allowed. */
    val allowInsurance: Boolean = true,

    /** Whether even money is offered on player Blackjack vs. dealer Ace. */
    val allowEvenMoney: Boolean = true,

    /** Blackjack payout multiplier (e.g., 1.5 for 3:2, 1.2 for 6:5). */
    val blackjackPayout: Double = 1.5,

    /** Insurance payout multiplier (typically 2.0 for 2:1). */
    val insurancePayout: Double = 2.0,

    /** Whether Five Card Charlie rule is in effect. */
    val fiveCardCharlie: Boolean = false,

    /** Number of cards for a Charlie win. */
    val charlieCardCount: Int = 5
) {
    init {
        require(numberOfDecks in 1..8) { "Number of decks must be between 1 and 8" }
        require(blackjackPayout > 0) { "Blackjack payout must be positive" }
        require(maxSplitHands in 2..4) { "Max split hands must be between 2 and 4" }
        require(reshuffleThreshold in 0.1..0.5) { "Reshuffle threshold must be between 0.1 and 0.5" }
    }
}

/** Rules for when doubling down is permitted. */
enum class DoubleDownRule {
    /** Can double on any first two cards. */
    ANY_TWO_CARDS,

    /** Can only double on totals of 9, 10, or 11. */
    NINE_TEN_ELEVEN,

    /** Can only double on totals of 10 or 11. */
    TEN_ELEVEN,

    /** Can only double on a total of 11. */
    ELEVEN_ONLY
}

/** Types of surrender options. */
enum class SurrenderType {
    /** No surrender allowed. */
    NONE,

    /** Can surrender before dealer checks for Blackjack. */
    EARLY,

    /** Can only surrender after dealer checks (and doesn't have Blackjack). */
    LATE
}
