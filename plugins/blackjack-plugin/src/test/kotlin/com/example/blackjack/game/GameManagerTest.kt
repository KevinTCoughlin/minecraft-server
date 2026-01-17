package com.example.blackjack.game

import org.junit.jupiter.api.Test
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GameManagerTest {

    @Test
    fun `can start a new game`() {
        val manager = GameManager()
        val playerId = UUID.randomUUID()

        val session = manager.startGame(playerId)

        assertNotNull(session)
        assertTrue(manager.hasActiveGame(playerId))
    }

    @Test
    fun `can retrieve active session`() {
        val manager = GameManager()
        val playerId = UUID.randomUUID()

        manager.startGame(playerId)
        val session = manager.getSession(playerId)

        assertNotNull(session)
    }

    @Test
    fun `no session for unknown player`() {
        val manager = GameManager()
        val playerId = UUID.randomUUID()

        assertNull(manager.getSession(playerId))
        assertFalse(manager.hasActiveGame(playerId))
    }

    @Test
    fun `ending game removes session`() {
        val manager = GameManager()
        val playerId = UUID.randomUUID()

        val session = manager.startGame(playerId)
        // Force the game to end
        session.stand()

        manager.endGame(playerId)

        assertFalse(manager.hasActiveGame(playerId))
        assertNull(manager.getSession(playerId))
    }

    @Test
    fun `stats are tracked per player`() {
        val manager = GameManager()
        val player1 = UUID.randomUUID()
        val player2 = UUID.randomUUID()

        val stats1 = manager.getStats(player1)
        val stats2 = manager.getStats(player2)

        stats1.recordResult(GameResult.PLAYER_WIN)

        assertEquals(1, stats1.wins)
        assertEquals(0, stats2.wins)
    }

    @Test
    fun `win streak is tracked`() {
        val manager = GameManager()
        val playerId = UUID.randomUUID()
        val stats = manager.getStats(playerId)

        stats.recordResult(GameResult.PLAYER_WIN)
        assertEquals(1, stats.currentWinStreak)

        stats.recordResult(GameResult.PLAYER_WIN)
        assertEquals(2, stats.currentWinStreak)

        stats.recordResult(GameResult.DEALER_WIN)
        assertEquals(0, stats.currentWinStreak)
        assertEquals(2, stats.bestWinStreak)
    }

    @Test
    fun `multiple players can play simultaneously`() {
        val manager = GameManager()
        val player1 = UUID.randomUUID()
        val player2 = UUID.randomUUID()

        manager.startGame(player1)
        manager.startGame(player2)

        assertEquals(2, manager.getActiveGameCount())
        assertTrue(manager.hasActiveGame(player1))
        assertTrue(manager.hasActiveGame(player2))
    }
}
