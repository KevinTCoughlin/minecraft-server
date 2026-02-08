package com.example.blackjack

import com.example.blackjack.commands.litecommands.*
import com.example.blackjack.game.DoubleDownRule
import com.example.blackjack.game.GameConfig
import com.example.blackjack.game.GameManager
import com.example.blackjack.game.SurrenderType
import com.example.blackjack.listeners.PlayerJoinListener
import dev.rollczi.litecommands.LiteCommands
import dev.rollczi.litecommands.bukkit.LiteBukkitFactory
import org.bukkit.command.CommandSender
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
        val gameplay = config.getConfigurationSection("gameplay") ?: return GameConfig()

        return GameConfig(
            numberOfDecks = gameplay.getInt("decks", 1).coerceIn(1, 8),
            reshuffleThreshold = gameplay.getDouble("reshuffle-threshold", 0.25).coerceIn(0.1, 0.5),
            dealerStandsOnSoft17 = gameplay.getBoolean("dealer-stands-on-soft-17", true),
            dealerPeeks = gameplay.getBoolean("dealer-peeks", true),
            allowDoubleDown = gameplay.getBoolean("allow-double-down", true),
            doubleDownOn = parseDoubleDownRule(gameplay.getString("double-down-on", "any")),
            allowDoubleAfterSplit = gameplay.getBoolean("allow-double-after-split", true),
            allowSplit = gameplay.getBoolean("allow-split", true),
            maxSplitHands = gameplay.getInt("max-split-hands", 4).coerceIn(2, 4),
            allowResplitAces = gameplay.getBoolean("allow-resplit-aces", false),
            allowHitSplitAces = gameplay.getBoolean("allow-hit-split-aces", false),
            allowSurrender = gameplay.getBoolean("allow-surrender", true),
            surrenderType = parseSurrenderType(gameplay.getString("surrender-type", "late")),
            allowInsurance = gameplay.getBoolean("allow-insurance", true),
            allowEvenMoney = gameplay.getBoolean("allow-even-money", true),
            blackjackPayout = gameplay.getDouble("blackjack-payout", 1.5),
            insurancePayout = gameplay.getDouble("insurance-payout", 2.0),
            fiveCardCharlie = gameplay.getBoolean("five-card-charlie", false),
            charlieCardCount = gameplay.getInt("charlie-card-count", 5).coerceIn(5, 7)
        )
    }

    private fun parseDoubleDownRule(value: String?): DoubleDownRule {
        return when (value?.lowercase()) {
            "9-10-11", "9_10_11", "nine-ten-eleven" -> DoubleDownRule.NINE_TEN_ELEVEN
            "10-11", "10_11", "ten-eleven" -> DoubleDownRule.TEN_ELEVEN
            "11", "eleven-only" -> DoubleDownRule.ELEVEN_ONLY
            else -> DoubleDownRule.ANY_TWO_CARDS
        }
    }

    private fun parseSurrenderType(value: String?): SurrenderType {
        return when (value?.lowercase()) {
            "early" -> SurrenderType.EARLY
            "none", "disabled" -> SurrenderType.NONE
            else -> SurrenderType.LATE
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
