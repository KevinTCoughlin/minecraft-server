package com.example.blackjack.commands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameResult
import com.example.blackjack.ui.ChatUI
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.format.NamedTextColor
import org.bukkit.command.Command
import org.bukkit.command.CommandExecutor
import org.bukkit.command.CommandSender
import org.bukkit.command.TabCompleter
import org.bukkit.entity.Player

class BlackjackCommand(private val plugin: BlackjackPlugin) : CommandExecutor, TabCompleter {

    private val gameManager get() = plugin.gameManager
    private val announcements get() = plugin.announcementManager

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        if (sender !is Player) {
            sender.sendMessage(Component.text("This command can only be used by players!", NamedTextColor.RED))
            return true
        }

        val subcommand = args.getOrNull(0)?.lowercase() ?: "start"

        when (subcommand) {
            "start" -> handleStart(sender)
            "hit" -> handleHit(sender)
            "stand" -> handleStand(sender)
            "stats" -> handleStats(sender)
            else -> {
                sender.sendMessage(Component.text("Unknown subcommand. Use: /bj [start|hit|stand|stats]", NamedTextColor.RED))
            }
        }

        return true
    }

    private fun handleStart(player: Player) {
        // End any existing game first
        if (gameManager.hasActiveGame(player.uniqueId)) {
            gameManager.endGame(player.uniqueId)
        }

        val session = gameManager.startGame(player.uniqueId)

        player.sendMessage(Component.empty())
        player.sendMessage(
            Component.text("Starting a new game of Blackjack!", NamedTextColor.GOLD)
        )
        player.sendMessage(Component.empty())

        ChatUI.sendGameDisplay(player, session)

        // Check if game already ended (player blackjack scenario)
        if (session.isFinished()) {
            val endResult = gameManager.endGame(player.uniqueId)
            endResult?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleHit(player: Player) {
        val session = gameManager.getSession(player.uniqueId)

        if (session == null) {
            player.sendMessage(
                Component.text("You don't have an active game! Use /bj to start one.", NamedTextColor.RED)
            )
            return
        }

        if (!session.isPlayerTurn()) {
            player.sendMessage(
                Component.text("It's not your turn to hit!", NamedTextColor.RED)
            )
            return
        }

        session.hit()
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished()) {
            val endResult = gameManager.endGame(player.uniqueId)
            endResult?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleStand(player: Player) {
        val session = gameManager.getSession(player.uniqueId)

        if (session == null) {
            player.sendMessage(
                Component.text("You don't have an active game! Use /bj to start one.", NamedTextColor.RED)
            )
            return
        }

        if (!session.isPlayerTurn()) {
            player.sendMessage(
                Component.text("It's not your turn!", NamedTextColor.RED)
            )
            return
        }

        session.stand()
        ChatUI.sendGameDisplay(player, session)
        val endResult = gameManager.endGame(player.uniqueId)
        endResult?.let { handleGameEnd(player, it) }
    }

    private fun handleGameEnd(player: Player, endResult: com.example.blackjack.game.GameManager.GameEndResult) {
        when (endResult.result) {
            GameResult.PLAYER_BLACKJACK -> {
                announcements.announceBlackjack(player)
            }
            GameResult.DEALER_BUST -> {
                announcements.announceDealerBust(player)
                announcements.announceWin(player, endResult.result)
            }
            GameResult.PLAYER_WIN -> {
                announcements.announceWin(player, endResult.result)
            }
            else -> { /* No announcement for losses/pushes */ }
        }

        // Check for win streak announcements
        if (endResult.winStreak > 0) {
            announcements.announceWinStreak(player, endResult.winStreak)
        }
    }

    private fun handleStats(player: Player) {
        val stats = gameManager.getStats(player.uniqueId)
        player.sendMessage(Component.empty())
        player.sendMessage(ChatUI.renderStats(stats))
    }

    override fun onTabComplete(
        sender: CommandSender,
        command: Command,
        alias: String,
        args: Array<out String>
    ): List<String> {
        if (args.size == 1) {
            val subcommands = listOf("start", "hit", "stand", "stats")
            return subcommands.filter { it.startsWith(args[0].lowercase()) }
        }
        return emptyList()
    }
}
