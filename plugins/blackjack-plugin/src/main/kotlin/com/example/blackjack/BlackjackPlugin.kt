package com.example.blackjack

import com.example.blackjack.commands.BlackjackCommand
import com.example.blackjack.game.GameManager
import org.bukkit.plugin.java.JavaPlugin

class BlackjackPlugin : JavaPlugin() {

    private lateinit var gameManager: GameManager

    override fun onEnable() {
        // Save default config if it doesn't exist
        saveDefaultConfig()

        // Initialize game manager
        gameManager = GameManager()

        // Register commands
        val blackjackCommand = BlackjackCommand(gameManager)
        getCommand("bj")?.setExecutor(blackjackCommand)
        getCommand("bj")?.tabCompleter = blackjackCommand

        logger.info("${description.name} v${description.version} has been enabled!")
        logger.info("Use /bj to start playing blackjack!")
    }

    override fun onDisable() {
        logger.info("${description.name} has been disabled!")
    }
}
