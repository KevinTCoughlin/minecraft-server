package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
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
@Command(name = "deal insurance")
class BlackjackInsuranceCommand(plugin: BlackjackPlugin) : BaseBlackjackCommand(plugin) {

    @Execute
    fun insurance(@Context player: Player, @Arg decision: String) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /deal to start one.")
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
                player.sendError("Usage: /deal insurance yes or /deal insurance no")
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
}
