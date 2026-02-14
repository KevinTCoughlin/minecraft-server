package com.example.blackjack

import com.charleskorn.kaml.Yaml
import com.charleskorn.kaml.YamlConfiguration
import com.example.blackjack.commands.litecommands.*
import com.example.blackjack.game.GameConfig
import com.example.blackjack.game.GameManager
import com.example.blackjack.listeners.PlayerJoinListener
import dev.rollczi.litecommands.LiteCommands
import dev.rollczi.litecommands.bukkit.LiteBukkitFactory
import kotlinx.serialization.Serializable
import org.bukkit.command.CommandSender
import org.bukkit.plugin.java.JavaPlugin

/**
 * Top-level config structure for kaml deserialization.
 * Only the `gameplay` section is deserialized; other sections are ignored via strictMode = false.
 */
@Serializable
private data class PluginConfig(
    val gameplay: GameConfig = GameConfig()
)

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

    /** LiteCommands instance for command management. */
    private lateinit var liteCommands: LiteCommands<CommandSender>

    override fun onEnable() {
        saveDefaultConfig()

        val gameConfig = loadGameConfig()
        gameManager = GameManager(gameConfig)
        announcementManager = AnnouncementManager(this)

        registerCommands()
        registerListeners()

        logger.info("${pluginMeta.name} v${pluginMeta.version} has been enabled!")
        logger.info("Use /deal to start playing blackjack!")
        logConfigInfo(gameConfig)
    }

    private fun loadGameConfig(): GameConfig {
        val configFile = dataFolder.resolve("config.yml")
        if (!configFile.exists()) return GameConfig()

        return try {
            val yaml = Yaml(configuration = YamlConfiguration(strictMode = false))
            val pluginConfig = yaml.decodeFromString(PluginConfig.serializer(), configFile.readText())
            pluginConfig.gameplay
        } catch (e: Exception) {
            logger.warning("Failed to parse config.yml, using defaults: ${e.message}")
            GameConfig()
        }
    }

    private fun logConfigInfo(config: GameConfig) {
        logger.info("Game configuration loaded:")
        logger.info("  - Decks: ${config.numberOfDecks}")
        logger.info("  - Dealer stands on soft 17: ${config.dealerStandsOnSoft17}")
        logger.info("  - Blackjack payout: ${config.blackjackPayout}x (${if (config.blackjackPayout == 1.5) "3:2" else "6:5"})")
        logger.info("  - Double down: ${config.allowDoubleDown} (${config.doubleDownOn})")
        logger.info("  - Split: ${config.allowSplit} (max ${config.maxSplitHands} hands)")
        logger.info("  - Surrender: ${config.surrenderType}")
        logger.info("  - Insurance: ${config.allowInsurance}")
    }

    override fun onDisable() {
        // Unregister LiteCommands
        if (::liteCommands.isInitialized) {
            liteCommands.unregister()
        }
        logger.info("${pluginMeta.name} has been disabled!")
    }

    private fun registerCommands() {
        liteCommands = LiteBukkitFactory.builder(this)
            .commands(
                BlackjackBaseCommand(this),
                BlackjackActionCommands(this),
                BlackjackInsuranceCommand(this),
                BlackjackStatsCommand(this),
                BlackjackRulesCommand(this)
            )
            .build()

        logger.info("LiteCommands initialized with 5 command handlers")
    }

    private fun registerListeners() {
        server.pluginManager.registerEvents(PlayerJoinListener(this), this)
    }
}
