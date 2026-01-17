package com.example.blackjack.commands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import com.example.blackjack.ui.ChatUI
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.format.NamedTextColor
import org.bukkit.command.Command
import org.bukkit.command.CommandExecutor
import org.bukkit.command.CommandSender
import org.bukkit.command.TabCompleter
import org.bukkit.entity.Player

/**
 * Handles the `/bj` command and its subcommands.
 */
class BlackjackCommand(private val plugin: BlackjackPlugin) : CommandExecutor, TabCompleter {

    private val gameManager get() = plugin.gameManager
    private val announcements get() = plugin.announcementManager

    companion object {
        private val SUBCOMMANDS = listOf("start", "hit", "stand", "stats")
    }

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        val player = sender as? Player ?: run {
            sender.sendMessage(Component.text("This command can only be used by players!", NamedTextColor.RED))
            return true
        }

        when (args.getOrNull(0)?.lowercase() ?: "start") {
            "start" -> handleStart(player)
            "hit" -> handleHit(player)
            "stand" -> handleStand(player)
            "stats" -> handleStats(player)
            else -> player.sendError("Unknown subcommand. Use: /bj [start|hit|stand|stats]")
        }

        return true
    }

    private fun handleStart(player: Player) {
        // End any existing game first
        if (player.uniqueId in gameManager) {
            gameManager.endGame(player.uniqueId)
        }

        val session = gameManager.startGame(player.uniqueId)

        player.sendMessage(Component.empty())
        player.sendMessage(Component.text("Starting a new game of Blackjack!", NamedTextColor.GOLD))
        player.sendMessage(Component.empty())

        ChatUI.sendGameDisplay(player, session)

        // Check if game already ended (player blackjack scenario)
        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleHit(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn to hit!")
            return
        }

        session.hit()
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleStand(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        session.stand()
        ChatUI.sendGameDisplay(player, session)
        gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
    }

    private fun handleGameEnd(player: Player, endResult: GameManager.GameEndResult) {
        when (endResult.result) {
            GameResult.PLAYER_BLACKJACK -> announcements.announceBlackjack(player)
            GameResult.DEALER_BUST -> {
                announcements.announceDealerBust(player)
                announcements.announceWin(player, endResult.result)
            }
            GameResult.PLAYER_WIN -> announcements.announceWin(player, endResult.result)
            else -> Unit // No announcement for losses/pushes
        }

        if (endResult.winStreak > 0) {
            announcements.announceWinStreak(player, endResult.winStreak)
        }
    }

    private fun handleStats(player: Player) {
        player.sendMessage(Component.empty())
        player.sendMessage(ChatUI.renderStats(gameManager.getStats(player.uniqueId)))
    }

    override fun onTabComplete(
        sender: CommandSender,
        command: Command,
        alias: String,
        args: Array<out String>
    ): List<String> = when {
        args.size == 1 -> SUBCOMMANDS.filter { it.startsWith(args[0], ignoreCase = true) }
        else -> emptyList()
    }

    private fun Player.sendError(message: String) {
        sendMessage(Component.text(message, NamedTextColor.RED))
    }
}
