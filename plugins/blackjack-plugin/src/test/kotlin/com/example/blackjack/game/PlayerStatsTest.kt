package com.example.blackjack.game

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class PlayerStatsTest {

    @Test
    fun `initial stats are zero`() {
        val stats = PlayerStats()
        assertEquals(0, stats.wins)
        assertEquals(0, stats.losses)
        assertEquals(0, stats.pushes)
        assertEquals(0, stats.blackjacks)
        assertEquals(0, stats.gamesPlayed)
        assertEquals(0, stats.currentWinStreak)
        assertEquals(0, stats.bestWinStreak)
    }

    @Test
    fun `player win increments wins and streak`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_WIN)

        assertEquals(1, stats.wins)
        assertEquals(1, stats.gamesPlayed)
        assertEquals(1, stats.currentWinStreak)
    }

    @Test
    fun `player blackjack increments wins and blackjacks`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_BLACKJACK)

        assertEquals(1, stats.wins)
        assertEquals(1, stats.blackjacks)
        assertEquals(1, stats.currentWinStreak)
    }

    @Test
    fun `dealer bust counts as win`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.DEALER_BUST)

        assertEquals(1, stats.wins)
        assertEquals(1, stats.currentWinStreak)
    }

    @Test
    fun `dealer win increments losses and resets streak`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_WIN)
        stats.recordResult(GameResult.PLAYER_WIN)
        stats.recordResult(GameResult.DEALER_WIN)

        assertEquals(2, stats.wins)
        assertEquals(1, stats.losses)
        assertEquals(0, stats.currentWinStreak)
        assertEquals(2, stats.bestWinStreak)
    }

    @Test
    fun `player bust counts as loss`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_BUST)

        assertEquals(1, stats.losses)
        assertEquals(0, stats.currentWinStreak)
    }

    @Test
    fun `push does not affect streak`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_WIN)
        stats.recordResult(GameResult.PUSH)

        assertEquals(1, stats.wins)
        assertEquals(1, stats.pushes)
        assertEquals(1, stats.currentWinStreak) // Unchanged
    }

    @Test
    fun `best streak is updated only when exceeded`() {
        val stats = PlayerStats()

        // Win 3 in a row
        repeat(3) { stats.recordResult(GameResult.PLAYER_WIN) }
        assertEquals(3, stats.bestWinStreak)

        // Lose
        stats.recordResult(GameResult.DEALER_WIN)
        assertEquals(3, stats.bestWinStreak)

        // Win 2 (less than best)
        repeat(2) { stats.recordResult(GameResult.PLAYER_WIN) }
        assertEquals(3, stats.bestWinStreak) // Still 3

        // Win 2 more (now 4 total, exceeds best)
        repeat(2) { stats.recordResult(GameResult.PLAYER_WIN) }
        assertEquals(4, stats.bestWinStreak)
    }

    @Test
    fun `games played includes all outcomes`() {
        val stats = PlayerStats()
        stats.recordResult(GameResult.PLAYER_WIN)
        stats.recordResult(GameResult.DEALER_WIN)
        stats.recordResult(GameResult.PUSH)
        stats.recordResult(GameResult.PLAYER_BLACKJACK)
        stats.recordResult(GameResult.PLAYER_BUST)
        stats.recordResult(GameResult.DEALER_BUST)

        assertEquals(6, stats.gamesPlayed)
    }
}
