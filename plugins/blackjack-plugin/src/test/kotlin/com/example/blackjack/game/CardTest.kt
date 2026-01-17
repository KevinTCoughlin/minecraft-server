package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CardTest {

    @Test
    fun `card values are correct`() {
        assertEquals(11, Card(Suit.SPADES, Rank.ACE).value)
        assertEquals(2, Card(Suit.HEARTS, Rank.TWO).value)
        assertEquals(10, Card(Suit.DIAMONDS, Rank.TEN).value)
        assertEquals(10, Card(Suit.CLUBS, Rank.JACK).value)
        assertEquals(10, Card(Suit.SPADES, Rank.QUEEN).value)
        assertEquals(10, Card(Suit.HEARTS, Rank.KING).value)
    }

    @Test
    fun `card display is correct`() {
        assertEquals("A♠", Card(Suit.SPADES, Rank.ACE).display)
        assertEquals("K♥", Card(Suit.HEARTS, Rank.KING).display)
        assertEquals("10♦", Card(Suit.DIAMONDS, Rank.TEN).display)
    }

    @Test
    fun `red suits are identified correctly`() {
        assertTrue(Suit.HEARTS.isRed)
        assertTrue(Suit.DIAMONDS.isRed)
        assertFalse(Suit.SPADES.isRed)
        assertFalse(Suit.CLUBS.isRed)
    }
}
