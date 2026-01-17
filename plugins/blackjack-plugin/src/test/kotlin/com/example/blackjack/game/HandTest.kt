package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HandTest {

    @Test
    fun `empty hand has value 0`() {
        val hand = Hand()
        assertEquals(0, hand.getValue())
    }

    @Test
    fun `single card value is correct`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.KING))
        assertEquals(10, hand.getValue())
    }

    @Test
    fun `multiple cards sum correctly`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.FIVE))
        hand.addCard(Card(Suit.HEARTS, Rank.THREE))
        assertEquals(8, hand.getValue())
    }

    @Test
    fun `ace counts as 11 when safe`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.ACE))
        hand.addCard(Card(Suit.HEARTS, Rank.FIVE))
        assertEquals(16, hand.getValue())
    }

    @Test
    fun `ace counts as 1 when 11 would bust`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.ACE))
        hand.addCard(Card(Suit.HEARTS, Rank.KING))
        hand.addCard(Card(Suit.DIAMONDS, Rank.FIVE))
        // ACE(1) + KING(10) + FIVE(5) = 16, not 26
        assertEquals(16, hand.getValue())
    }

    @Test
    fun `multiple aces adjust correctly`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.ACE))
        hand.addCard(Card(Suit.HEARTS, Rank.ACE))
        // Two aces: first is 11, second would make 22, so both become 1+1=12
        // Actually: 11+11=22 bust, so 11+1=12
        assertEquals(12, hand.getValue())
    }

    @Test
    fun `blackjack is detected`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.ACE))
        hand.addCard(Card(Suit.HEARTS, Rank.KING))
        assertTrue(hand.isBlackjack())
        assertEquals(21, hand.getValue())
    }

    @Test
    fun `21 with more than 2 cards is not blackjack`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.SEVEN))
        hand.addCard(Card(Suit.HEARTS, Rank.SEVEN))
        hand.addCard(Card(Suit.DIAMONDS, Rank.SEVEN))
        assertEquals(21, hand.getValue())
        assertFalse(hand.isBlackjack())
    }

    @Test
    fun `bust is detected`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.KING))
        hand.addCard(Card(Suit.HEARTS, Rank.QUEEN))
        hand.addCard(Card(Suit.DIAMONDS, Rank.FIVE))
        assertTrue(hand.isBust())
        assertEquals(25, hand.getValue())
    }

    @Test
    fun `clear removes all cards`() {
        val hand = Hand()
        hand.addCard(Card(Suit.SPADES, Rank.ACE))
        hand.addCard(Card(Suit.HEARTS, Rank.KING))
        hand.clear()
        assertEquals(0, hand.getValue())
        assertEquals(0, hand.size())
    }
}
