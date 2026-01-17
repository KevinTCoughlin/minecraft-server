package com.example.blackjack.game

enum class Suit(val symbol: String) {
    SPADES("♠"),
    HEARTS("♥"),
    DIAMONDS("♦"),
    CLUBS("♣");

    val isRed: Boolean
        get() = this == HEARTS || this == DIAMONDS
}

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
    KING("K", 10)
}

data class Card(val suit: Suit, val rank: Rank) {
    val value: Int
        get() = rank.value

    val display: String
        get() = "${rank.symbol}${suit.symbol}"

    override fun toString(): String = display
}
