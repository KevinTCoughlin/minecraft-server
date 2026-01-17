package com.example.plugin

import org.bukkit.Material
import org.bukkit.event.EventHandler
import org.bukkit.event.Listener
import org.bukkit.event.block.BlockBreakEvent

class BlockBreakListener(private val plugin: ExamplePlugin) : Listener {

    @EventHandler
    fun onBlockBreak(event: BlockBreakEvent) {
        val block = event.block
        val player = event.player

        // Example: Notify when diamond ore is broken
        if (block.type == Material.DIAMOND_ORE || block.type == Material.DEEPSLATE_DIAMOND_ORE) {
            if (plugin.config.getBoolean("announce-diamond-mining", true)) {
                plugin.server.broadcastMessage(
                    "${player.name} found diamonds at ${block.x}, ${block.y}, ${block.z}!"
                )
            }
        }
    }
}
