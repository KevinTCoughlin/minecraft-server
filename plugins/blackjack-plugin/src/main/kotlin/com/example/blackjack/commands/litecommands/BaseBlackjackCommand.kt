package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.RED
import org.bukkit.entity.Player

/**
 * Base class for blackjack command handlers
 * Provides common functionality like game end handling and error messaging
 */
abstract class BaseBlackjackCommand(protected val plugin: BlackjackPlugin) {

    protected val gameManager: GameManager
        get() = plugin.gameManager

    /**
     * Handles the end of a game, announcing results to the player
     */
    protected fun handleGameEnd(player: Player, endResult: GameManager.GameEndResult) {
        val result = endResult.result
        val announcements = plugin.announcementManager

        when (result) {
            GameResult.PLAYER_BLACKJACK -> announcements.announceBlackjack(player)
            GameResult.DEALER_BUST -> {
                announcements.announceDealerBust(player)
                announcements.announceWin(player, result)
            }
            GameResult.PLAYER_WIN -> announcements.announceWin(player, result)
            else -> Unit
        }

        if (endResult.winStreak > 0) {
            announcements.announceWinStreak(player, endResult.winStreak)
        }
    }

    /**
     * Sends an error message to the player in red
     */
    protected fun Player.sendError(message: String) {
        sendMessage(text(message, RED))
    }
}
