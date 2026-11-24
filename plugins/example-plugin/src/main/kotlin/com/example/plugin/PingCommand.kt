package com.example.plugin

import org.bukkit.command.Command
import org.bukkit.command.CommandExecutor
import org.bukkit.command.CommandSender
import org.bukkit.entity.Player

class PingCommand : CommandExecutor {

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        if (sender is Player) {
            sender.sendMessage(pingMessage(sender.ping))
        } else {
            sender.sendMessage(consolePingMessage())
        }
        return true
    }
}
