package com.example.blackjack.game

class Deck {
    private val cards: MutableList<Card> = mutableListOf()

    init {
        reset()
    }

    fun reset() {
        cards.clear()
        for (suit in Suit.entries) {
            for (rank in Rank.entries) {
                cards.add(Card(suit, rank))
            }
        }
        shuffle()
    }

    fun shuffle() {
        cards.shuffle()
    }

    fun draw(): Card {
        if (cards.isEmpty()) {
            reset()
        }
        return cards.removeAt(cards.lastIndex)
    }

    fun cardsRemaining(): Int = cards.size
}
