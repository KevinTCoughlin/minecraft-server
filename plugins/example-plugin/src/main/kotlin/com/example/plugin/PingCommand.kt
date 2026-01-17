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
            val ping = sender.ping
            sender.sendMessage("Pong! Your ping is ${ping}ms")
        } else {
            sender.sendMessage("Pong! (Console has no ping)")
        }
        return true
    }
}
