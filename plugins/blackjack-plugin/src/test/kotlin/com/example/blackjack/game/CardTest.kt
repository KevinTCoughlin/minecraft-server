package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CardTest {

    @Test
    fun `card values are correct`() {
        assertEquals(11, Card(Rank.ACE, Suit.SPADES).value)
        assertEquals(2, Card(Rank.TWO, Suit.HEARTS).value)
        assertEquals(10, Card(Rank.TEN, Suit.DIAMONDS).value)
        assertEquals(10, Card(Rank.JACK, Suit.CLUBS).value)
        assertEquals(10, Card(Rank.QUEEN, Suit.SPADES).value)
        assertEquals(10, Card(Rank.KING, Suit.HEARTS).value)
    }

    @Test
    fun `card display is correct`() {
        assertEquals("A♠", Card(Rank.ACE, Suit.SPADES).display)
        assertEquals("K♥", Card(Rank.KING, Suit.HEARTS).display)
        assertEquals("10♦", Card(Rank.TEN, Suit.DIAMONDS).display)
    }

    @Test
    fun `red suits are identified correctly`() {
        assertTrue(Suit.HEARTS.isRed)
        assertTrue(Suit.DIAMONDS.isRed)
        assertFalse(Suit.SPADES.isRed)
        assertFalse(Suit.CLUBS.isRed)
    }
}
