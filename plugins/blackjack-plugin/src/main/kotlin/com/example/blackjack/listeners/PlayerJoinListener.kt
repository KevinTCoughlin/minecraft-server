package com.example.blackjack.listeners

import com.example.blackjack.BlackjackPlugin
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.bukkit.event.EventHandler
import org.bukkit.event.Listener
import org.bukkit.event.player.PlayerJoinEvent

/**
 * Sends a welcome message to players when they join.
 */
class PlayerJoinListener(private val plugin: BlackjackPlugin) : Listener {

    private val serializer = LegacyComponentSerializer.legacyAmpersand()
    private val config get() = plugin.config

    @EventHandler
    fun onPlayerJoin(event: PlayerJoinEvent) {
        if (!config.getBoolean("join-message.enabled", true)) return

        val messages = config.getStringList("join-message.messages")
        if (messages.isEmpty()) return

        val delay = config.getLong("join-message.delay", 40L)

        plugin.server.scheduler.runTaskLater(plugin, Runnable {
            event.player.takeIf { it.isOnline }?.let { player ->
                player.sendMessage(Component.empty())
                messages.map(serializer::deserialize).forEach(player::sendMessage)
                player.sendMessage(Component.empty())
            }
        }, delay)
    }
}
