package com.example.blackjack.listeners

import com.example.blackjack.BlackjackPlugin
import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.bukkit.event.EventHandler
import org.bukkit.event.Listener
import org.bukkit.event.player.PlayerJoinEvent

class PlayerJoinListener(private val plugin: BlackjackPlugin) : Listener {

    @EventHandler
    fun onPlayerJoin(event: PlayerJoinEvent) {
        if (!plugin.config.getBoolean("join-message.enabled", true)) {
            return
        }

        val delay = plugin.config.getLong("join-message.delay", 40L)
        val messages = plugin.config.getStringList("join-message.messages")

        if (messages.isEmpty()) {
            return
        }

        // Schedule the welcome message with a delay
        plugin.server.scheduler.runTaskLater(plugin, Runnable {
            val player = event.player
            if (player.isOnline) {
                player.sendMessage(LegacyComponentSerializer.legacyAmpersand().deserialize(""))
                for (message in messages) {
                    player.sendMessage(
                        LegacyComponentSerializer.legacyAmpersand().deserialize(message)
                    )
                }
                player.sendMessage(LegacyComponentSerializer.legacyAmpersand().deserialize(""))
            }
        }, delay)
    }
}
