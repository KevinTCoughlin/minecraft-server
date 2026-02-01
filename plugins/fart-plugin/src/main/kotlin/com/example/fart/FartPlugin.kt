package com.example.fart

import org.bukkit.plugin.java.JavaPlugin

class FartPlugin : JavaPlugin() {

    override fun onEnable() {
        // Register the /fart command
        getCommand("fart")?.setExecutor(FartCommand())

        logger.info("${description.name} v${description.version} has been enabled!")
        logger.info("The /fart command is now available!")
    }

    override fun onDisable() {
        logger.info("${description.name} has been disabled!")
    }
}
