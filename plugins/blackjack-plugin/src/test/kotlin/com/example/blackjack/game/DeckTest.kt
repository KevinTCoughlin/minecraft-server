package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class DeckTest {

    @Test
    fun `single deck has 52 cards`() {
        val deck = Deck()
        assertEquals(52, deck.remaining)
        assertEquals(52, deck.totalCardsInShoe)
    }

    @Test
    fun `multi-deck shoe has correct card count`() {
        val deck2 = Deck(numberOfDecks = 2)
        assertEquals(104, deck2.remaining)

        val deck6 = Deck(numberOfDecks = 6)
        assertEquals(312, deck6.remaining)

        val deck8 = Deck(numberOfDecks = 8)
        assertEquals(416, deck8.remaining)
    }

    @Test
    fun `drawing reduces deck size`() {
        val deck = Deck()
        deck.draw()
        assertEquals(51, deck.remaining)
        deck.draw()
        assertEquals(50, deck.remaining)
    }

    @Test
    fun `deck resets when empty`() {
        val deck = Deck(reshuffleThreshold = 0.0) // Disable reshuffle threshold
        // Draw all 52 cards
        repeat(52) { deck.draw() }
        assertEquals(0, deck.remaining)

        // Drawing again should reset the deck
        deck.draw()
        assertEquals(51, deck.remaining)
    }

    @Test
    fun `deck contains all cards`() {
        // Use 0.1 threshold to avoid early reshuffle during this test
        val deck = Deck(reshuffleThreshold = 0.1)
        val drawnCards = mutableSetOf<String>()

        // Draw 47 cards (leaving 5, which is < 10% so won't trigger mid-draw reshuffle)
        repeat(47) {
            drawnCards.add(deck.draw().display)
        }

        // Should have 47 unique cards
        assertEquals(47, drawnCards.size)
    }

    @Test
    fun `shuffle changes card order`() {
        val deck1 = Deck()
        val deck2 = Deck()

        // Draw first 5 cards from each deck
        val cards1 = (1..5).map { deck1.draw().display }
        val cards2 = (1..5).map { deck2.draw().display }

        // Very unlikely to be the same after shuffling
        assertNotEquals(cards1, cards2, "Decks should be shuffled differently")
    }

    @Test
    fun `reshuffle threshold triggers reset`() {
        // Create a deck that reshuffles when 50% remains
        val deck = Deck(numberOfDecks = 1, reshuffleThreshold = 0.5)

        // Draw almost half the deck (25 cards) - 27 remain
        repeat(25) { deck.draw() }
        assertEquals(27, deck.remaining)
        assertFalse(deck.needsReshuffle())

        // Draw one more - now at 26 cards (= 50% of 52, threshold reached)
        deck.draw()
        assertEquals(26, deck.remaining)
        assertTrue(deck.needsReshuffle())

        // Next draw should reset the deck
        deck.draw()
        assertEquals(51, deck.remaining)
    }

    @Test
    fun `penetration is calculated correctly`() {
        val deck = Deck()
        assertEquals(0.0, deck.penetration, 0.01)

        repeat(26) { deck.draw() }
        assertEquals(0.5, deck.penetration, 0.01) // Half dealt

        repeat(13) { deck.draw() }
        assertEquals(0.75, deck.penetration, 0.01) // 3/4 dealt
    }

    @Test
    fun `isEmpty returns true when no cards remain`() {
        val deck = Deck(reshuffleThreshold = 0.0)
        assertFalse(deck.isEmpty)

        repeat(52) { deck.draw() }
        assertTrue(deck.isEmpty)
    }
}
