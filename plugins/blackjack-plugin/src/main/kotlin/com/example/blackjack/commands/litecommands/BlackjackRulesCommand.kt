package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.Component.newline
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.*
import net.kyori.adventure.text.format.TextDecoration
import org.bukkit.entity.Player

/**
 * Handles rules subcommand to display house rules
 */
@Command(name = "bj rules")
class BlackjackRulesCommand(plugin: BlackjackPlugin) : BaseBlackjackCommand(plugin) {

    @Execute
    fun rules(@Context player: Player) {
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
                if (config.allowDoubleDown) "Yes (${formatEnumName(config.doubleDownOn.name)})" else "No",
                if (config.allowDoubleDown) GREEN else RED
            )).append(newline())
            .append(text("  Split: ", WHITE)).append(text(
                if (config.allowSplit) "Yes (up to ${config.maxSplitHands} hands)" else "No",
                if (config.allowSplit) GREEN else RED
            )).append(newline())
            .append(text("  Surrender: ", WHITE)).append(text(
                if (config.allowSurrender) "${formatEnumName(config.surrenderType.name)} surrender" else "No",
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

    /**
     * Formats an enum name for display (e.g., "ANY_TWO_CARDS" -> "any two cards")
     */
    private fun formatEnumName(name: String): String = 
        name.lowercase().replace('_', ' ')
}
