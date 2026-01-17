package com.example.plugin

import net.kyori.adventure.text.Component
import net.kyori.adventure.text.format.NamedTextColor
import org.bukkit.event.EventHandler
import org.bukkit.event.EventPriority
import org.bukkit.event.Listener
import org.bukkit.event.player.PlayerJoinEvent

class PlayerJoinListener(private val plugin: ExamplePlugin) : Listener {

    @EventHandler(priority = EventPriority.NORMAL)
    fun onPlayerJoin(event: PlayerJoinEvent) {
        val player = event.player
        val welcomeMessage = plugin.config.getString("welcome-message", "Welcome to the server!")

        // Send personalized welcome message
        player.sendMessage(
            Component.text()
                .append(Component.text("[Server] ", NamedTextColor.GOLD))
                .append(Component.text(welcomeMessage.replace("{player}", player.name), NamedTextColor.GREEN))
                .build()
        )

        // Log to console
        plugin.logger.info("${player.name} joined the server!")

        // Optional: Play a sound
        if (plugin.config.getBoolean("play-join-sound", true)) {
            player.playSound(
                player.location,
                org.bukkit.Sound.ENTITY_PLAYER_LEVELUP,
                1.0f,
                1.0f
            )
        }
    }
}
