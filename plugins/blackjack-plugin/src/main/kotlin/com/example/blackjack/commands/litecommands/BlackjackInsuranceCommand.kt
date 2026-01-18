package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import com.example.blackjack.ui.ChatUI
import dev.rollczi.litecommands.annotations.argument.Arg
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.*
import org.bukkit.entity.Player

/**
 * Handles insurance decision subcommand
 */
@Command(name = "bj insurance")
class BlackjackInsuranceCommand(private val plugin: BlackjackPlugin) {

    private val gameManager: GameManager
        get() = plugin.gameManager

    @Execute
    fun insurance(@Context player: Player, @Arg decision: String) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (!session.isWaitingForInsurance) {
            player.sendError("Insurance is not being offered right now.")
            return
        }

        when (decision.lowercase()) {
            "yes", "y" -> {
                session.takeInsurance()
                player.sendMessage(text("Insurance taken!", GREEN))
            }
            "no", "n" -> {
                session.declineInsurance()
                player.sendMessage(text("Insurance declined.", YELLOW))
            }
            else -> {
                player.sendError("Usage: /bj insurance yes or /bj insurance no")
                return
            }
        }

        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            // Dealer had blackjack
            if (session.insuranceTaken && session.dealerHasBlackjack) {
                player.sendMessage(text("Dealer has Blackjack! Insurance pays 2:1.", GOLD))
            } else if (session.dealerHasBlackjack) {
                player.sendMessage(text("Dealer has Blackjack!", RED))
            }
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleGameEnd(player: Player, endResult: GameManager.GameEndResult) {
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

    private fun Player.sendError(message: String) {
        sendMessage(text(message, RED))
    }
}
