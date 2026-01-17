package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class DeckTest {

    @Test
    fun `deck has 52 cards`() {
        val deck = Deck()
        assertEquals(52, deck.cardsRemaining())
    }

    @Test
    fun `drawing reduces deck size`() {
        val deck = Deck()
        deck.draw()
        assertEquals(51, deck.cardsRemaining())
        deck.draw()
        assertEquals(50, deck.cardsRemaining())
    }

    @Test
    fun `deck resets when empty`() {
        val deck = Deck()
        // Draw all 52 cards
        repeat(52) { deck.draw() }
        assertEquals(0, deck.cardsRemaining())

        // Drawing again should reset the deck
        deck.draw()
        assertEquals(51, deck.cardsRemaining())
    }

    @Test
    fun `deck contains all cards`() {
        val deck = Deck()
        val drawnCards = mutableSetOf<String>()

        repeat(52) {
            drawnCards.add(deck.draw().display)
        }

        // Should have 52 unique cards
        assertEquals(52, drawnCards.size)
    }

    @Test
    fun `shuffle changes card order`() {
        val deck1 = Deck()
        val deck2 = Deck()

        // Draw first 5 cards from each deck
        val cards1 = (1..5).map { deck1.draw().display }
        val cards2 = (1..5).map { deck2.draw().display }

        // Very unlikely to be the same after shuffling
        // (technically possible but statistically improbable)
        assertNotEquals(cards1, cards2, "Decks should be shuffled differently")
    }
}
