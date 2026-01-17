package com.example.blackjack

import com.example.blackjack.commands.BlackjackCommand
import com.example.blackjack.game.GameManager
import com.example.blackjack.listeners.PlayerJoinListener
import org.bukkit.plugin.java.JavaPlugin

class BlackjackPlugin : JavaPlugin() {

    lateinit var gameManager: GameManager
        private set
    lateinit var announcementManager: AnnouncementManager
        private set

    override fun onEnable() {
        // Save default config if it doesn't exist
        saveDefaultConfig()

        // Initialize managers
        gameManager = GameManager()
        announcementManager = AnnouncementManager(this)

        // Register commands
        val blackjackCommand = BlackjackCommand(this)
        getCommand("bj")?.setExecutor(blackjackCommand)
        getCommand("bj")?.tabCompleter = blackjackCommand

        // Register listeners
        server.pluginManager.registerEvents(PlayerJoinListener(this), this)

        logger.info("${pluginMeta.name} v${pluginMeta.version} has been enabled!")
        logger.info("Use /bj to start playing blackjack!")
    }

    override fun onDisable() {
        logger.info("${pluginMeta.name} has been disabled!")
    }
}
