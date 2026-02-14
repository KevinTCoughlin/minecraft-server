package com.example.blackjack.game

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Configuration options for a Blackjack game.
 *
 * Provides sensible defaults matching standard casino rules.
 */
@Serializable
data class GameConfig(
    /** Number of decks to use (1-8). */
    @SerialName("decks")
    val numberOfDecks: Int = 1,

    /** Reshuffle when this fraction of cards remain (0.1-0.5). */
    @SerialName("reshuffle-threshold")
    val reshuffleThreshold: Double = 0.25,

    /** Whether the dealer stands on soft 17. */
    @SerialName("dealer-stands-on-soft-17")
    val dealerStandsOnSoft17: Boolean = true,

    /** Whether the dealer peeks for Blackjack when showing Ace/10. */
    @SerialName("dealer-peeks")
    val dealerPeeks: Boolean = true,

    /** Whether players can double down. */
    @SerialName("allow-double-down")
    val allowDoubleDown: Boolean = true,

    /** Restriction on when doubling down is allowed. */
    @SerialName("double-down-on")
    val doubleDownOn: DoubleDownRule = DoubleDownRule.ANY_TWO_CARDS,

    /** Whether players can double after splitting. */
    @SerialName("allow-double-after-split")
    val allowDoubleAfterSplit: Boolean = true,

    /** Whether players can split pairs. */
    @SerialName("allow-split")
    val allowSplit: Boolean = true,

    /** Maximum number of hands from splitting (2-4). */
    @SerialName("max-split-hands")
    val maxSplitHands: Int = 4,

    /** Whether players can re-split Aces. */
    @SerialName("allow-resplit-aces")
    val allowResplitAces: Boolean = false,

    /** Whether players can hit after splitting Aces. */
    @SerialName("allow-hit-split-aces")
    val allowHitSplitAces: Boolean = false,

    /** Whether surrender is allowed. */
    @SerialName("allow-surrender")
    val allowSurrender: Boolean = true,

    /** The type of surrender allowed. */
    @SerialName("surrender-type")
    val surrenderType: SurrenderType = SurrenderType.LATE,

    /** Whether insurance bets are allowed. */
    @SerialName("allow-insurance")
    val allowInsurance: Boolean = true,

    /** Whether even money is offered on player Blackjack vs. dealer Ace. */
    @SerialName("allow-even-money")
    val allowEvenMoney: Boolean = true,

    /** Blackjack payout multiplier (e.g., 1.5 for 3:2, 1.2 for 6:5). */
    @SerialName("blackjack-payout")
    val blackjackPayout: Double = 1.5,

    /** Insurance payout multiplier (typically 2.0 for 2:1). */
    @SerialName("insurance-payout")
    val insurancePayout: Double = 2.0,

    /** Whether Five Card Charlie rule is in effect. */
    @SerialName("five-card-charlie")
    val fiveCardCharlie: Boolean = false,

    /** Number of cards for a Charlie win. */
    @SerialName("charlie-card-count")
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
@Serializable
enum class DoubleDownRule {
    /** Can double on any first two cards. */
    @SerialName("any")
    ANY_TWO_CARDS,

    /** Can only double on totals of 9, 10, or 11. */
    @SerialName("9-10-11")
    NINE_TEN_ELEVEN,

    /** Can only double on totals of 10 or 11. */
    @SerialName("10-11")
    TEN_ELEVEN,

    /** Can only double on a total of 11. */
    @SerialName("11")
    ELEVEN_ONLY
}

/** Types of surrender options. */
@Serializable
enum class SurrenderType {
    /** No surrender allowed. */
    @SerialName("none")
    NONE,

    /** Can surrender before dealer checks for Blackjack. */
    @SerialName("early")
    EARLY,

    /** Can only surrender after dealer checks (and doesn't have Blackjack). */
    @SerialName("late")
    LATE
}
