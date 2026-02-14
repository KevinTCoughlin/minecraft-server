package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import com.example.blackjack.game.GameSession
import com.example.blackjack.ui.ChatUI
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
     * Validates that the player has an active session, is not waiting for insurance,
     * and it's their turn, then executes the given action.
     */
    protected inline fun Player.withValidSession(action: (GameSession) -> Unit) {
        val session = gameManager[uniqueId] ?: run {
            sendError("You don't have an active game! Use /deal to start one.")
            return
        }
        if (session.isWaitingForInsurance) {
            sendError("You must decide on insurance first! Use /deal insurance yes or /deal insurance no")
            return
        }
        if (!session.isPlayerTurn) {
            sendError("It's not your turn!")
            return
        }
        action(session)
    }

    protected fun finishAction(player: Player, session: GameSession) {
        ChatUI.sendGameDisplay(player, session)
        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    /**
     * Sends an error message to the player in red
     */
    protected fun Player.sendError(message: String) {
        sendMessage(text(message, RED))
    }
}
