package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HandTest {

    @Test
    fun `empty hand has value 0`() {
        val hand = Hand()
        assertEquals(0, hand.value)
    }

    @Test
    fun `single card value is correct`() {
        val hand = Hand()
        hand.addCard(Card(Rank.KING, Suit.SPADES))
        assertEquals(10, hand.value)
    }

    @Test
    fun `multiple cards sum correctly`() {
        val hand = Hand()
        hand.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand.addCard(Card(Rank.THREE, Suit.HEARTS))
        assertEquals(8, hand.value)
    }

    @Test
    fun `ace counts as 11 when safe`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.FIVE, Suit.HEARTS))
        assertEquals(16, hand.value)
        assertTrue(hand.isSoft)
    }

    @Test
    fun `ace counts as 1 when 11 would bust`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.KING, Suit.HEARTS))
        hand.addCard(Card(Rank.FIVE, Suit.DIAMONDS))
        // ACE(1) + KING(10) + FIVE(5) = 16, not 26
        assertEquals(16, hand.value)
        assertFalse(hand.isSoft)
    }

    @Test
    fun `multiple aces adjust correctly`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.ACE, Suit.HEARTS))
        // Two aces: 11+1=12
        assertEquals(12, hand.value)
        assertTrue(hand.isSoft)
    }

    @Test
    fun `blackjack is detected`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.KING, Suit.HEARTS))
        assertTrue(hand.isBlackjack)
        assertEquals(21, hand.value)
    }

    @Test
    fun `21 with more than 2 cards is not blackjack`() {
        val hand = Hand()
        hand.addCard(Card(Rank.SEVEN, Suit.SPADES))
        hand.addCard(Card(Rank.SEVEN, Suit.HEARTS))
        hand.addCard(Card(Rank.SEVEN, Suit.DIAMONDS))
        assertEquals(21, hand.value)
        assertFalse(hand.isBlackjack)
    }

    @Test
    fun `21 from split is not blackjack`() {
        val hand = Hand(isFromSplit = true)
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.KING, Suit.HEARTS))
        assertEquals(21, hand.value)
        assertFalse(hand.isBlackjack)
    }

    @Test
    fun `bust is detected`() {
        val hand = Hand()
        hand.addCard(Card(Rank.KING, Suit.SPADES))
        hand.addCard(Card(Rank.QUEEN, Suit.HEARTS))
        hand.addCard(Card(Rank.FIVE, Suit.DIAMONDS))
        assertTrue(hand.isBust)
        assertEquals(25, hand.value)
    }

    @Test
    fun `clear removes all cards and resets state`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.KING, Suit.HEARTS))
        hand.markDoubledDown()
        hand.clear()
        assertEquals(0, hand.value)
        assertEquals(0, hand.size)
        assertFalse(hand.hasDoubledDown)
    }

    // --- Soft hand tests ---

    @Test
    fun `soft hand is detected with ace counted as 11`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.SIX, Suit.HEARTS))
        assertEquals(17, hand.value)
        assertTrue(hand.isSoft) // Soft 17
    }

    @Test
    fun `hard hand when ace must count as 1`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.SIX, Suit.HEARTS))
        hand.addCard(Card(Rank.KING, Suit.DIAMONDS))
        assertEquals(17, hand.value)
        assertFalse(hand.isSoft) // Hard 17
    }

    @Test
    fun `hand without aces is not soft`() {
        val hand = Hand()
        hand.addCard(Card(Rank.KING, Suit.SPADES))
        hand.addCard(Card(Rank.SEVEN, Suit.HEARTS))
        assertEquals(17, hand.value)
        assertFalse(hand.isSoft)
    }

    // --- Pair tests ---

    @Test
    fun `pair is detected`() {
        val hand = Hand()
        hand.addCard(Card(Rank.EIGHT, Suit.SPADES))
        hand.addCard(Card(Rank.EIGHT, Suit.HEARTS))
        assertTrue(hand.isPair)
    }

    @Test
    fun `non-pair is not detected as pair`() {
        val hand = Hand()
        hand.addCard(Card(Rank.EIGHT, Suit.SPADES))
        hand.addCard(Card(Rank.NINE, Suit.HEARTS))
        assertFalse(hand.isPair)
    }

    @Test
    fun `three cards is not a pair`() {
        val hand = Hand()
        hand.addCard(Card(Rank.EIGHT, Suit.SPADES))
        hand.addCard(Card(Rank.EIGHT, Suit.HEARTS))
        hand.addCard(Card(Rank.EIGHT, Suit.DIAMONDS))
        assertFalse(hand.isPair)
    }

    // --- Double down tests ---

    @Test
    fun `can double down on any two cards by default`() {
        val hand = Hand()
        hand.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand.addCard(Card(Rank.THREE, Suit.HEARTS))
        assertTrue(hand.canDoubleDown(DoubleDownRule.ANY_TWO_CARDS, true))
    }

    @Test
    fun `can double down on 9-10-11 only`() {
        val hand9 = Hand()
        hand9.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand9.addCard(Card(Rank.FOUR, Suit.HEARTS))
        assertTrue(hand9.canDoubleDown(DoubleDownRule.NINE_TEN_ELEVEN, true))

        val hand8 = Hand()
        hand8.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand8.addCard(Card(Rank.THREE, Suit.HEARTS))
        assertFalse(hand8.canDoubleDown(DoubleDownRule.NINE_TEN_ELEVEN, true))
    }

    @Test
    fun `cannot double down after more than two cards`() {
        val hand = Hand()
        hand.addCard(Card(Rank.THREE, Suit.SPADES))
        hand.addCard(Card(Rank.THREE, Suit.HEARTS))
        hand.addCard(Card(Rank.FIVE, Suit.DIAMONDS))
        assertFalse(hand.canDoubleDown(DoubleDownRule.ANY_TWO_CARDS, true))
    }

    @Test
    fun `cannot double down twice`() {
        val hand = Hand()
        hand.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand.addCard(Card(Rank.SIX, Suit.HEARTS))
        hand.markDoubledDown()
        assertFalse(hand.canDoubleDown(DoubleDownRule.ANY_TWO_CARDS, true))
    }

    @Test
    fun `cannot double after split when not allowed`() {
        val hand = Hand(isFromSplit = true)
        hand.addCard(Card(Rank.FIVE, Suit.SPADES))
        hand.addCard(Card(Rank.SIX, Suit.HEARTS))
        assertFalse(hand.canDoubleDown(DoubleDownRule.ANY_TWO_CARDS, allowDoubleAfterSplit = false))
    }

    // --- Split hand tests ---

    @Test
    fun `split hand tracks origin`() {
        val hand = Hand(isFromSplit = true, isSplitAces = true)
        assertTrue(hand.isFromSplit)
        assertTrue(hand.isSplitAces)
    }

    // --- Surrender tests ---

    @Test
    fun `hand tracks surrender state`() {
        val hand = Hand()
        hand.addCard(Card(Rank.TEN, Suit.SPADES))
        hand.addCard(Card(Rank.SIX, Suit.HEARTS))
        assertFalse(hand.hasSurrendered)
        hand.markSurrendered()
        assertTrue(hand.hasSurrendered)
    }

    // --- removeLastCard tests ---

    @Test
    fun `removeLastCard removes and returns last card`() {
        val hand = Hand()
        hand.addCard(Card(Rank.ACE, Suit.SPADES))
        hand.addCard(Card(Rank.KING, Suit.HEARTS))

        val removed = hand.removeLastCard()
        assertEquals(Rank.KING, removed?.rank)
        assertEquals(1, hand.size)
    }

}
