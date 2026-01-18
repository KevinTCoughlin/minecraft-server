package com.example.blackjack.game

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks a player's Blackjack statistics.
 */
data class PlayerStats(
    var wins: Int = 0,
    var losses: Int = 0,
    var pushes: Int = 0,
    var blackjacks: Int = 0,
    var surrenders: Int = 0,
    var currentWinStreak: Int = 0,
    var bestWinStreak: Int = 0
) {
    /** Total number of games played. */
    val gamesPlayed: Int get() = wins + losses + pushes + surrenders

    /**
     * Records a game result and updates statistics.
     *
     * @param result The outcome of the game.
     * @return The current win streak after recording.
     */
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
            GameResult.SURRENDERED -> {
                surrenders++
                currentWinStreak = 0
            }
        }
        bestWinStreak = maxOf(bestWinStreak, currentWinStreak)
        return currentWinStreak
    }
}

/**
 * Manages active Blackjack game sessions and player statistics.
 *
 * Thread-safe for concurrent access.
 *
 * @property config The game configuration to use for all sessions.
 */
class GameManager(private val config: GameConfig = GameConfig()) {

    private val activeSessions = ConcurrentHashMap<UUID, GameSession>()
    private val playerStats = ConcurrentHashMap<UUID, PlayerStats>()

    /** The number of currently active games. */
    val activeGameCount: Int get() = activeSessions.size

    /** The current game configuration. */
    val gameConfig: GameConfig get() = config

    /**
     * Starts a new game for the specified player.
     *
     * @param playerId The player's unique ID.
     * @return The newly created game session.
     */
    fun startGame(playerId: UUID): GameSession =
        GameSession(playerId, config).also { activeSessions[playerId] = it }

    /**
     * Gets the active session for a player, if one exists.
     *
     * @param playerId The player's unique ID.
     * @return The active session, or `null` if none exists.
     */
    operator fun get(playerId: UUID): GameSession? = activeSessions[playerId]

    /**
     * Checks if a player has an active game.
     *
     * @param playerId The player's unique ID.
     */
    operator fun contains(playerId: UUID): Boolean = activeSessions.containsKey(playerId)

    /** Result of ending a game, containing the outcome and current win streak. */
    data class GameEndResult(
        val result: GameResult,
        val winStreak: Int
    )

    /**
     * Ends a player's active game and records the result.
     *
     * @param playerId The player's unique ID.
     * @return The game result and win streak, or `null` if no active game.
     */
    fun endGame(playerId: UUID): GameEndResult? {
        val session = activeSessions.remove(playerId) ?: return null
        val result = session.result ?: return null
        val winStreak = getStats(playerId).recordResult(result)
        return GameEndResult(result, winStreak)
    }

    /**
     * Gets the statistics for a player, creating them if necessary.
     *
     * @param playerId The player's unique ID.
     */
    fun getStats(playerId: UUID): PlayerStats =
        playerStats.getOrPut(playerId) { PlayerStats() }

    // === Legacy Compatibility Methods ===

    /** Legacy method - use `get(playerId)` instead. */
    fun getSession(playerId: UUID): GameSession? = get(playerId)

    /** Legacy method - use `playerId in gameManager` instead. */
    fun hasActiveGame(playerId: UUID): Boolean = playerId in this
}
