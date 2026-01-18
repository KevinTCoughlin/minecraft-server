package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.ui.ChatUI
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import net.kyori.adventure.text.Component
import org.bukkit.entity.Player

/**
 * Handles stats subcommand to display player statistics
 */
@Command(name = "bj stats")
class BlackjackStatsCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun stats(@Context player: Player) {
        player.sendMessage(Component.empty())
        player.sendMessage(ChatUI.renderStats(plugin.gameManager.getStats(player.uniqueId)))
    }
}
