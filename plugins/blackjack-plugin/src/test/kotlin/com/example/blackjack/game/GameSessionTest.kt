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
        val config = GameConfig(allowInsurance = false)
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
}
