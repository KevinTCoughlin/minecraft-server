package com.example.blackjack.game

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class PlayerStats(
    var wins: Int = 0,
    var losses: Int = 0,
    var pushes: Int = 0,
    var blackjacks: Int = 0,
    var currentWinStreak: Int = 0,
    var bestWinStreak: Int = 0
) {
    val gamesPlayed: Int
        get() = wins + losses + pushes

    fun recordResult(result: GameResult): Int {
        when (result) {
            GameResult.PLAYER_WIN, GameResult.DEALER_BUST -> {
                wins++
                currentWinStreak++
            }
            GameResult.PLAYER_BLACKJACK -> {
                wins++
                blackjacks++
                currentWinStreak++
            }
            GameResult.DEALER_WIN, GameResult.PLAYER_BUST -> {
                losses++
                currentWinStreak = 0
            }
            GameResult.PUSH -> pushes++
        }
        if (currentWinStreak > bestWinStreak) {
            bestWinStreak = currentWinStreak
        }
        return currentWinStreak
    }
}

class GameManager {
    private val activeSessions: ConcurrentHashMap<UUID, GameSession> = ConcurrentHashMap()
    private val playerStats: ConcurrentHashMap<UUID, PlayerStats> = ConcurrentHashMap()

    fun startGame(playerId: UUID): GameSession {
        val session = GameSession(playerId)
        activeSessions[playerId] = session
        return session
    }

    fun getSession(playerId: UUID): GameSession? = activeSessions[playerId]

    fun hasActiveGame(playerId: UUID): Boolean = activeSessions.containsKey(playerId)

    data class GameEndResult(
        val result: GameResult,
        val winStreak: Int
    )

    fun endGame(playerId: UUID): GameEndResult? {
        val session = activeSessions.remove(playerId) ?: return null
        val result = session.result ?: return null
        val winStreak = getOrCreateStats(playerId).recordResult(result)
        return GameEndResult(result, winStreak)
    }

    fun getStats(playerId: UUID): PlayerStats = getOrCreateStats(playerId)

    private fun getOrCreateStats(playerId: UUID): PlayerStats {
        return playerStats.getOrPut(playerId) { PlayerStats() }
    }

    fun getActiveGameCount(): Int = activeSessions.size
}
