package com.example.blackjack

import com.example.blackjack.game.GameResult
import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.bukkit.entity.Player

class AnnouncementManager(private val plugin: BlackjackPlugin) {

    private val serializer = LegacyComponentSerializer.legacyAmpersand()

    fun announceBlackjack(player: Player) {
        if (!plugin.config.getBoolean("announcements.blackjack.enabled", true)) {
            return
        }

        val message = plugin.config.getString("announcements.blackjack.message",
            "&6%player% &ejust got a &6BLACKJACK&e!")
            ?.replace("%player%", player.name)
            ?: return

        broadcast(message, player)
    }

    fun announceWin(player: Player, result: GameResult) {
        if (!plugin.config.getBoolean("announcements.win.enabled", false)) {
            return
        }

        val message = plugin.config.getString("announcements.win.message",
            "&a%player% &2won at blackjack!")
            ?.replace("%player%", player.name)
            ?: return

        broadcast(message, player)
    }

    fun announceDealerBust(player: Player) {
        if (!plugin.config.getBoolean("announcements.dealer-bust.enabled", false)) {
            return
        }

        val message = plugin.config.getString("announcements.dealer-bust.message",
            "&a%player%'s &2dealer busted!")
            ?.replace("%player%", player.name)
            ?: return

        broadcast(message, player)
    }

    fun announceWinStreak(player: Player, streak: Int) {
        if (!plugin.config.getBoolean("announcements.win-streak.enabled", true)) {
            return
        }

        val threshold = plugin.config.getInt("announcements.win-streak.threshold", 3)
        if (streak < threshold) {
            return
        }

        val message = plugin.config.getString("announcements.win-streak.message",
            "&6%player% &eis on a &6%streak%-win streak &eat blackjack!")
            ?.replace("%player%", player.name)
            ?.replace("%streak%", streak.toString())
            ?: return

        broadcast(message, player)
    }

    private fun broadcast(message: String, player: Player) {
        val component = serializer.deserialize(message)

        if (plugin.config.getBoolean("announcements.broadcast-enabled", true)) {
            plugin.server.broadcast(component)
        } else {
            player.sendMessage(component)
        }
    }
}
