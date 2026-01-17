package com.example.blackjack

import com.example.blackjack.commands.BlackjackCommand
import com.example.blackjack.game.GameManager
import com.example.blackjack.listeners.PlayerJoinListener
import org.bukkit.plugin.java.JavaPlugin

/**
 * Main plugin class for the Blackjack minigame.
 *
 * Provides chat-based Blackjack with player statistics and announcements.
 */
class BlackjackPlugin : JavaPlugin() {

    /** Manages active game sessions and player statistics. */
    lateinit var gameManager: GameManager
        private set

    /** Handles broadcasting game events to players. */
    lateinit var announcementManager: AnnouncementManager
        private set

    override fun onEnable() {
        saveDefaultConfig()

        gameManager = GameManager()
        announcementManager = AnnouncementManager(this)

        registerCommands()
        registerListeners()

        logger.info("${pluginMeta.name} v${pluginMeta.version} has been enabled!")
        logger.info("Use /bj to start playing blackjack!")
    }

    override fun onDisable() {
        logger.info("${pluginMeta.name} has been disabled!")
    }

    private fun registerCommands() {
        val blackjackCommand = BlackjackCommand(this)
        getCommand("bj")?.apply {
            setExecutor(blackjackCommand)
            tabCompleter = blackjackCommand
        }
    }

    private fun registerListeners() {
        server.pluginManager.registerEvents(PlayerJoinListener(this), this)
    }
}
