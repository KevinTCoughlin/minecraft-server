package com.example.blackjack

import com.example.blackjack.game.GameResult
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.bukkit.entity.Player

/**
 * Handles broadcasting game events like wins and streaks.
 */
class AnnouncementManager(private val plugin: BlackjackPlugin) {

    private val serializer = LegacyComponentSerializer.legacyAmpersand()
    private val config get() = plugin.config

    /** Announces when a player gets a natural Blackjack. */
    fun announceBlackjack(player: Player) {
        announce(
            player = player,
            configPath = "announcements.blackjack",
            defaultMessage = "&6%player% &ejust got a &6BLACKJACK&e!"
        )
    }

    /** Announces when a player wins a hand. */
    @Suppress("UNUSED_PARAMETER")
    fun announceWin(player: Player, result: GameResult) {
        announce(
            player = player,
            configPath = "announcements.win",
            defaultMessage = "&a%player% &2won at blackjack!",
            defaultEnabled = false
        )
    }

    /** Announces when the dealer busts. */
    fun announceDealerBust(player: Player) {
        announce(
            player = player,
            configPath = "announcements.dealer-bust",
            defaultMessage = "&a%player%'s &2dealer busted!",
            defaultEnabled = false
        )
    }

    /** Announces notable win streaks. */
    fun announceWinStreak(player: Player, streak: Int) {
        val threshold = config.getInt("announcements.win-streak.threshold", 3)
        if (streak < threshold) return

        announce(
            player = player,
            configPath = "announcements.win-streak",
            defaultMessage = "&6%player% &eis on a &6%streak%-win streak &eat blackjack!",
            extraReplacements = mapOf("%streak%" to streak.toString())
        )
    }

    private fun announce(
        player: Player,
        configPath: String,
        defaultMessage: String,
        defaultEnabled: Boolean = true,
        extraReplacements: Map<String, String> = emptyMap()
    ) {
        if (!config.getBoolean("$configPath.enabled", defaultEnabled)) return

        val message = config.getString("$configPath.message", defaultMessage)
            ?.replace("%player%", player.name)
            ?.let { msg -> extraReplacements.entries.fold(msg) { acc, (k, v) -> acc.replace(k, v) } }
            ?: return

        broadcast(message, player)
    }

    private fun broadcast(message: String, player: Player) {
        val component: Component = serializer.deserialize(message)

        if (config.getBoolean("announcements.broadcast-enabled", true)) {
            plugin.server.broadcast(component)
        } else {
            player.sendMessage(component)
        }
    }
}
