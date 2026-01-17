package com.example.plugin

import org.bukkit.plugin.java.JavaPlugin

class ExamplePlugin : JavaPlugin() {

    override fun onEnable() {
        // Save default config if it doesn't exist
        saveDefaultConfig()

        // Register commands
        getCommand("hello")?.setExecutor(HelloCommand(this))
        getCommand("ping")?.setExecutor(PingCommand())

        // Register event listeners
        server.pluginManager.registerEvents(PlayerJoinListener(this), this)
        server.pluginManager.registerEvents(BlockBreakListener(this), this)

        logger.info("${description.name} v${description.version} has been enabled!")
        logger.info("Welcome message: ${config.getString("welcome-message")}")
    }

    override fun onDisable() {
        logger.info("${description.name} has been disabled!")
    }
}
