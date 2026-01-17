package com.example.plugin

import org.bukkit.command.Command
import org.bukkit.command.CommandExecutor
import org.bukkit.command.CommandSender
import org.bukkit.entity.Player

class HelloCommand(private val plugin: ExamplePlugin) : CommandExecutor {

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        val message = if (args.isNotEmpty()) {
            "Hello, ${args.joinToString(" ")}!"
        } else if (sender is Player) {
            "Hello, ${sender.name}!"
        } else {
            "Hello, World!"
        }

        // Get prefix from config
        val prefix = plugin.config.getString("message-prefix", "[Example]")
        sender.sendMessage("$prefix $message")

        return true
    }
}
