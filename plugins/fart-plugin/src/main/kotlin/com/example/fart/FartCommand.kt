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
            val player = sender
            
            // Play a fart-like sound effect using Minecraft's built-in sounds
            // ENTITY_RAVAGER_STUNNED is a guttural sound that works well for this
            player.world.playSound(
                player.location,
                Sound.ENTITY_RAVAGER_STUNNED,
                1.0f,  // volume
                0.5f   // pitch (lower pitch makes it sound more like a fart)
            )
            
            // Send a message to the player
            player.sendMessage("§6💨 *Fart noise* 💨")
            
            // Optionally broadcast to nearby players
            val nearbyPlayers = player.world.getNearbyEntities(
                player.location, 
                20.0, 
                20.0, 
                20.0
            ).filterIsInstance<Player>().filter { it != player }
            
            nearbyPlayers.forEach { nearbyPlayer ->
                nearbyPlayer.sendMessage("§e${player.name} farted! 💨")
            }
            
        } else {
            sender.sendMessage("Only players can use this command!")
        }
        return true
    }
}
