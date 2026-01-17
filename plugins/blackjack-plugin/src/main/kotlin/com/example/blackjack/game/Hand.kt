package com.example.blackjack.game

class Hand {
    private val cards: MutableList<Card> = mutableListOf()

    fun addCard(card: Card) {
        cards.add(card)
    }

    fun getCards(): List<Card> = cards.toList()

    fun getValue(): Int {
        var total = 0
        var aces = 0

        for (card in cards) {
            total += card.value
            if (card.rank == Rank.ACE) {
                aces++
            }
        }

        // Convert aces from 11 to 1 as needed to avoid bust
        while (total > 21 && aces > 0) {
            total -= 10
            aces--
        }

        return total
    }

    fun isBust(): Boolean = getValue() > 21

    fun isBlackjack(): Boolean = cards.size == 2 && getValue() == 21

    fun clear() {
        cards.clear()
    }

    fun size(): Int = cards.size
}
