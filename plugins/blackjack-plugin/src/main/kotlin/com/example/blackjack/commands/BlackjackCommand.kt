package com.example.blackjack.commands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.GameResult
import com.example.blackjack.ui.ChatUI
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.Component.newline
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor
import net.kyori.adventure.text.format.NamedTextColor.*
import net.kyori.adventure.text.format.TextDecoration
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
        private val SUBCOMMANDS = listOf("start", "hit", "stand", "double", "split", "surrender", "insurance", "stats", "rules")
        private val INSURANCE_OPTIONS = listOf("yes", "no")
    }

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        val player = sender as? Player ?: run {
            sender.sendMessage(text("This command can only be used by players!", RED))
            return true
        }

        when (args.getOrNull(0)?.lowercase() ?: "start") {
            "start" -> handleStart(player)
            "hit" -> handleHit(player)
            "stand" -> handleStand(player)
            "double" -> handleDouble(player)
            "split" -> handleSplit(player)
            "surrender" -> handleSurrender(player)
            "insurance" -> handleInsurance(player, args.getOrNull(1))
            "stats" -> handleStats(player)
            "rules" -> handleRules(player)
            else -> player.sendError("Unknown subcommand. Use: /bj [start|hit|stand|double|split|surrender|stats|rules]")
        }

        return true
    }

    private fun handleStart(player: Player) {
        if (player.uniqueId in gameManager) {
            gameManager.endGame(player.uniqueId)
        }

        val session = gameManager.startGame(player.uniqueId)

        player.sendMessage(Component.empty())
        player.sendMessage(text("Starting a new game of Blackjack!", GOLD))
        player.sendMessage(Component.empty())

        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleHit(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first! Use /bj insurance yes or /bj insurance no")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn to hit!")
            return
        }

        if (!session.canHit()) {
            player.sendError("You can't hit right now (split aces only get one card).")
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

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first! Use /bj insurance yes or /bj insurance no")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        session.stand()
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleDouble(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canDoubleDown()) {
            player.sendError("You can't double down right now. Double is only available on your first two cards.")
            return
        }

        session.doubleDown()
        player.sendMessage(text("Doubled down! Drawing one card...", GOLD))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleSplit(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canSplit()) {
            player.sendError("You can't split right now. Split is only available when you have a pair.")
            return
        }

        session.split()
        player.sendMessage(text("Split! Now playing hand ${session.getCurrentHandNumber()} of ${session.getHandCount()}", AQUA))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleSurrender(player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canSurrender()) {
            player.sendError("You can't surrender right now. Surrender is only available on your first two cards.")
            return
        }

        session.surrender()
        player.sendMessage(text("Surrendered. Half your bet has been returned.", GRAY))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    private fun handleInsurance(player: Player, decision: String?) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (!session.isWaitingForInsurance) {
            player.sendError("Insurance is not being offered right now.")
            return
        }

        when (decision?.lowercase()) {
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
        when (endResult.result) {
            GameResult.PLAYER_BLACKJACK -> announcements.announceBlackjack(player)
            GameResult.DEALER_BUST -> {
                announcements.announceDealerBust(player)
                announcements.announceWin(player, endResult.result)
            }
            GameResult.PLAYER_WIN -> announcements.announceWin(player, endResult.result)
            else -> Unit
        }

        if (endResult.winStreak > 0) {
            announcements.announceWinStreak(player, endResult.winStreak)
        }
    }

    private fun handleStats(player: Player) {
        player.sendMessage(Component.empty())
        player.sendMessage(ChatUI.renderStats(gameManager.getStats(player.uniqueId)))
    }

    private fun handleRules(player: Player) {
        val config = gameManager.gameConfig
        val divider = text("═══════════════════════════════", GOLD)

        val message = Component.empty()
            .append(divider).append(newline())
            .append(text("       House Rules", YELLOW).decorate(TextDecoration.BOLD)).append(newline())
            .append(divider).append(newline())
            .append(text("  Decks: ", WHITE)).append(text("${config.numberOfDecks}", AQUA)).append(newline())
            .append(text("  Blackjack pays: ", WHITE)).append(text(
                if (config.blackjackPayout == 1.5) "3:2" else "6:5",
                if (config.blackjackPayout == 1.5) GREEN else RED
            )).append(newline())
            .append(text("  Dealer: ", WHITE)).append(text(
                if (config.dealerStandsOnSoft17) "Stands on soft 17" else "Hits on soft 17",
                if (config.dealerStandsOnSoft17) GREEN else YELLOW
            )).append(newline())
            .append(text("  Double down: ", WHITE)).append(text(
                if (config.allowDoubleDown) "Yes (${config.doubleDownOn.name.lowercase().replace('_', ' ')})" else "No",
                if (config.allowDoubleDown) GREEN else RED
            )).append(newline())
            .append(text("  Split: ", WHITE)).append(text(
                if (config.allowSplit) "Yes (up to ${config.maxSplitHands} hands)" else "No",
                if (config.allowSplit) GREEN else RED
            )).append(newline())
            .append(text("  Surrender: ", WHITE)).append(text(
                if (config.allowSurrender) "${config.surrenderType.name.lowercase()} surrender" else "No",
                if (config.allowSurrender) YELLOW else RED
            )).append(newline())
            .append(text("  Insurance: ", WHITE)).append(text(
                if (config.allowInsurance) "Yes (pays 2:1)" else "No",
                if (config.allowInsurance) YELLOW else RED
            )).append(newline())
            .apply {
                if (config.fiveCardCharlie) {
                    append(text("  Five Card Charlie: ", WHITE))
                    append(text("Yes", GREEN)).append(newline())
                }
            }
            .append(divider)

        player.sendMessage(Component.empty())
        player.sendMessage(message)
    }

    override fun onTabComplete(
        sender: CommandSender,
        command: Command,
        alias: String,
        args: Array<out String>
    ): List<String> = when {
        args.size == 1 -> SUBCOMMANDS.filter { it.startsWith(args[0], ignoreCase = true) }
        args.size == 2 && args[0].equals("insurance", ignoreCase = true) ->
            INSURANCE_OPTIONS.filter { it.startsWith(args[1], ignoreCase = true) }
        else -> emptyList()
    }

    private fun Player.sendError(message: String) {
        sendMessage(text(message, RED))
    }
}
