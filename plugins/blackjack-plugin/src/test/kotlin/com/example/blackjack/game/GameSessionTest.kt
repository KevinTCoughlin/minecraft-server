package com.example.blackjack.game

import org.junit.jupiter.api.Test
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class GameSessionTest {

    private fun createSession(config: GameConfig = GameConfig()): GameSession {
        return GameSession(UUID.randomUUID(), config)
    }

    @Test
    fun `new session deals 4 cards total`() {
        val session = createSession()
        assertEquals(2, session.playerHand.size)
        assertEquals(2, session.dealerHand.size)
    }

    @Test
    fun `hit adds card to player hand`() {
        val session = createSession()
        val initialSize = session.playerHand.size

        if (session.isPlayerTurn) {
            session.hit()
            assertEquals(initialSize + 1, session.playerHand.size)
        }
    }

    @Test
    fun `stand ends player turn`() {
        val config = GameConfig(allowInsurance = false, dealerPeeks = false)
        val session = createSession(config)

        if (session.isPlayerTurn && !session.playerHand.isBlackjack) {
            session.stand()
            assertTrue(session.isFinished)
        }
    }

    @Test
    fun `bust ends the game`() {
        val config = GameConfig(allowInsurance = false, dealerPeeks = false)
        val session = createSession(config)

        // Hit until bust
        while (session.isPlayerTurn && !session.playerHand.isBust) {
            session.hit()
        }

        if (session.playerHand.isBust) {
            assertTrue(session.isFinished)
            assertEquals(GameResult.PLAYER_BUST, session.result)
        }
    }

    @Test
    fun `double down draws exactly one card`() {
        val config = GameConfig(
            allowDoubleDown = true,
            doubleDownOn = DoubleDownRule.ANY_TWO_CARDS,
            allowInsurance = false
        )
        val session = createSession(config)

        if (session.isPlayerTurn && session.canDoubleDown()) {
            val initialSize = session.playerHand.size
            session.doubleDown()
            assertEquals(initialSize + 1, session.playerHand.size)
            assertTrue(session.playerHand.hasDoubledDown)
        }
    }

    @Test
    fun `surrender ends game with surrendered result`() {
        val config = GameConfig(
            allowSurrender = true,
            surrenderType = SurrenderType.LATE,
            allowInsurance = false,
            dealerPeeks = false
        )
        val session = createSession(config)

        if (session.isPlayerTurn && session.canSurrender()) {
            session.surrender()
            assertTrue(session.isFinished)
            assertEquals(GameResult.SURRENDERED, session.result)
            assertTrue(session.playerHand.hasSurrendered)
        }
    }

    @Test
    fun `game state tracking`() {
        // With dealerPeeks on, a dealer Blackjack under an Ace/10 up card ends the game at deal time
        val config = GameConfig(allowInsurance = false, dealerPeeks = false)
        val session = createSession(config)

        // Should start in player turn (unless blackjack)
        if (!session.playerHand.isBlackjack) {
            assertTrue(session.isPlayerTurn)
            assertFalse(session.isFinished)
        }
    }

    @Test
    fun `hand results populated after game ends`() {
        val config = GameConfig(allowInsurance = false, dealerPeeks = false)
        val session = createSession(config)

        if (session.isPlayerTurn) {
            session.stand()
        }

        assertTrue(session.isFinished)
        assertTrue(session.handResults.isNotEmpty())
        assertNotNull(session.result)
    }

    @Test
    fun `config affects game behavior - number of decks`() {
        val config = GameConfig(numberOfDecks = 6)
        val session = createSession(config)

        // 6 decks = 312 cards, minus 4 dealt
        assertEquals(308, session.deck.remaining)
    }

    @Test
    fun `can query available actions`() {
        val config = GameConfig(
            allowDoubleDown = true,
            allowSplit = true,
            allowSurrender = true,
            allowInsurance = false
        )
        val session = createSession(config)

        if (session.isPlayerTurn) {
            // canHit should be true for player turn
            assertTrue(session.canHit())

            // canDoubleDown depends on hand
            // canSplit depends on having a pair
            // canSurrender depends on initial hand
        }
    }

    @Test
    fun `hand count and current hand number tracking`() {
        val session = createSession()

        assertEquals(1, session.getHandCount())
        assertEquals(1, session.getCurrentHandNumber())
    }

    @Test
    fun `player hands list contains active hand`() {
        val session = createSession()

        assertEquals(1, session.playerHands.size)
        assertEquals(session.playerHand, session.playerHands[0])
    }

    /**
     * A single-deck shoe whose first draws are [draws], in order. The deal goes
     * player, dealer (hole), player, dealer (up card); later draws stay random.
     */
    private fun riggedDeck(vararg draws: Card) = Deck(shuffler = { cards ->
        cards.shuffle()
        draws.forEach { cards.remove(it) }
        cards.addAll(draws.reversed())
    })

    private fun card(rank: Rank) = Card(rank, Suit.SPADES)

    @Test
    fun `dealer does not draw against a player blackjack`() {
        // Player A-K, dealer 6 (hole) + 5 (up): a total the dealer would normally hit
        val deck = riggedDeck(card(Rank.ACE), Card(Rank.SIX, Suit.HEARTS), card(Rank.KING), Card(Rank.FIVE, Suit.HEARTS))
        val session = GameSession(UUID.randomUUID(), GameConfig(), deck)

        assertTrue(session.isFinished)
        assertEquals(2, session.dealerHand.size)
        assertEquals(48, session.deck.remaining)
        assertEquals(GameResult.PLAYER_BLACKJACK, session.result)
    }

    @Test
    fun `player blackjack pushes an unpeeked dealer blackjack`() {
        // Player A-K, dealer A (hole) + Q (up) with peeking off, so only the settle catches it
        val deck = riggedDeck(card(Rank.ACE), Card(Rank.ACE, Suit.HEARTS), card(Rank.KING), Card(Rank.QUEEN, Suit.HEARTS))
        val session = GameSession(UUID.randomUUID(), GameConfig(dealerPeeks = false), deck)

        assertTrue(session.isFinished)
        assertEquals(2, session.dealerHand.size)
        assertEquals(GameResult.PUSH, session.result)
    }

    @Test
    fun `dealer does not draw against a five-card charlie`() {
        // Player 2-3 hits 2, 3, 4 for a 14-point Charlie; dealer 6 (hole) + 5 (up) would normally hit
        val deck = riggedDeck(
            card(Rank.TWO), Card(Rank.SIX, Suit.HEARTS), card(Rank.THREE), Card(Rank.FIVE, Suit.HEARTS),
            Card(Rank.TWO, Suit.HEARTS), Card(Rank.THREE, Suit.HEARTS), card(Rank.FOUR)
        )
        val session = GameSession(UUID.randomUUID(), GameConfig(fiveCardCharlie = true, charlieCardCount = 5), deck)

        repeat(3) { session.hit() }

        assertTrue(session.isFinished)
        assertEquals(5, session.playerHand.size)
        assertEquals(2, session.dealerHand.size)
        assertEquals(45, session.deck.remaining)
        assertEquals(GameResult.PLAYER_WIN, session.result)
    }

    @Test
    fun `dealer still draws when a hand depends on the total`() {
        // Player K-Q (20) stands, dealer 6 (hole) + 5 (up) = 11 must hit
        val deck = riggedDeck(card(Rank.KING), Card(Rank.SIX, Suit.HEARTS), card(Rank.QUEEN), Card(Rank.FIVE, Suit.HEARTS))
        val session = GameSession(UUID.randomUUID(), GameConfig(), deck)

        assertTrue(session.isPlayerTurn)
        session.stand()

        assertTrue(session.isFinished)
        assertTrue(session.dealerHand.size > 2)
    }
}
