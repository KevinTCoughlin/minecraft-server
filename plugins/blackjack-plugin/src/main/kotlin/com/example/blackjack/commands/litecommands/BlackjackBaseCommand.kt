package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import dev.rollczi.litecommands.annotations.permission.Permission
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.*
import org.bukkit.entity.Player

/**
 * Base command class for /bj
 * Handles the main command execution when no subcommand is specified
 */
@Command(name = "bj", aliases = ["blackjack"])
@Permission("blackjack.play")
class BlackjackBaseCommand(private val plugin: BlackjackPlugin) {

    private val gameManager: GameManager
        get() = plugin.gameManager

    /**
     * Default executor when /bj is called without arguments
     * Starts a new game or restarts if one is already active
     */
    @Execute
    fun start(@Context player: Player) {
        // End existing game if any
        if (player.uniqueId in gameManager) {
            gameManager.endGame(player.uniqueId)
        }

        val session = gameManager.startGame(player.uniqueId)

        player.sendMessage(Component.empty())
        player.sendMessage(text("Starting a new game of Blackjack!", GOLD))
        player.sendMessage(Component.empty())

        com.example.blackjack.ui.ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { endResult ->
                handleGameEnd(player, endResult)
            }
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
}
