package com.example.blackjack.game

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class PlayerStats(
    var wins: Int = 0,
    var losses: Int = 0,
    var pushes: Int = 0,
    var blackjacks: Int = 0
) {
    val gamesPlayed: Int
        get() = wins + losses + pushes

    fun recordResult(result: GameResult) {
        when (result) {
            GameResult.PLAYER_WIN, GameResult.DEALER_BUST -> wins++
            GameResult.PLAYER_BLACKJACK -> {
                wins++
                blackjacks++
            }
            GameResult.DEALER_WIN, GameResult.PLAYER_BUST -> losses++
            GameResult.PUSH -> pushes++
        }
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

    fun endGame(playerId: UUID) {
        val session = activeSessions.remove(playerId)
        session?.result?.let { result ->
            getOrCreateStats(playerId).recordResult(result)
        }
    }

    fun getStats(playerId: UUID): PlayerStats = getOrCreateStats(playerId)

    private fun getOrCreateStats(playerId: UUID): PlayerStats {
        return playerStats.getOrPut(playerId) { PlayerStats() }
    }

    fun getActiveGameCount(): Int = activeSessions.size
}
