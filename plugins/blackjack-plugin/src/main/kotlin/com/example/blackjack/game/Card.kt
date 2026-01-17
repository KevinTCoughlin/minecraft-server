package com.example.blackjack.game

/**
 * Represents the four suits in a standard deck of cards.
 *
 * @property symbol The Unicode symbol for this suit.
 */
enum class Suit(val symbol: String) {
    SPADES("♠"),
    HEARTS("♥"),
    DIAMONDS("♦"),
    CLUBS("♣");

    /** Returns `true` if this suit is red (hearts or diamonds). */
    val isRed: Boolean get() = this in setOf(HEARTS, DIAMONDS)
}

/**
 * Represents card ranks with their display symbols and base values.
 *
 * @property symbol The display character(s) for this rank.
 * @property value The base Blackjack value (Aces default to 11).
 */
enum class Rank(val symbol: String, val value: Int) {
    ACE("A", 11),
    TWO("2", 2),
    THREE("3", 3),
    FOUR("4", 4),
    FIVE("5", 5),
    SIX("6", 6),
    SEVEN("7", 7),
    EIGHT("8", 8),
    NINE("9", 9),
    TEN("10", 10),
    JACK("J", 10),
    QUEEN("Q", 10),
    KING("K", 10);

    /** Returns `true` if this rank is a face card (Jack, Queen, or King). */
    val isFaceCard: Boolean get() = this in setOf(JACK, QUEEN, KING)
}

/**
 * Represents a playing card with a suit and rank.
 *
 * @property suit The card's suit.
 * @property rank The card's rank.
 */
data class Card(val rank: Rank, val suit: Suit) {

    /** The Blackjack value of this card. */
    val value: Int get() = rank.value

    /** A human-readable display string (e.g., "A♠"). */
    val display: String get() = "${rank.symbol}${suit.symbol}"

    override fun toString(): String = display
}
