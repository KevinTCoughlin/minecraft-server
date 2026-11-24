package com.example.fart

import org.bukkit.Sound
import org.bukkit.command.Command
import org.bukkit.command.CommandExecutor
import org.bukkit.command.CommandSender
import org.bukkit.entity.Player

class FartCommand : CommandExecutor {

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        if (sender is Player) {
            // Play a fart-like sound effect using Minecraft's built-in sounds
            // ENTITY_RAVAGER_STUNNED is a guttural sound that works well for this
            sender.world.playSound(
                sender.location,
                Sound.ENTITY_RAVAGER_STUNNED,
                1.0f,  // volume
                0.5f   // pitch (lower pitch makes it sound more like a fart)
            )

            sender.sendMessage(fartSelfMessage())

            val nearbyPlayers = sender.world.getNearbyEntities(
                sender.location,
                20.0,
                20.0,
                20.0
            ).filterIsInstance<Player>().filter { it != sender }

            nearbyPlayers.forEach { nearbyPlayer ->
                nearbyPlayer.sendMessage(fartNearbyMessage(sender.name))
            }
        } else {
            sender.sendMessage(fartPlayersOnlyMessage())
        }
        return true
    }
}
