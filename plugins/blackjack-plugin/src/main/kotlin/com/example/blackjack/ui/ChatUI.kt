package com.example.blackjack.ui

import com.example.blackjack.game.*
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.Component.newline
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.event.ClickEvent
import net.kyori.adventure.text.event.HoverEvent
import net.kyori.adventure.text.format.NamedTextColor
import net.kyori.adventure.text.format.NamedTextColor.*
import net.kyori.adventure.text.format.TextDecoration
import org.bukkit.entity.Player

/**
 * Renders Blackjack game UI components for chat display.
 */
object ChatUI {

    private val DIVIDER = text("═══════════════════════════════", GOLD)

    /** Renders a single card with suit-appropriate coloring. */
    fun renderCard(card: Card): Component {
        val color = if (card.suit.isRed) RED else WHITE
        return text("[${card.display}]", color)
    }

    /** Renders a face-down card. */
    fun renderHiddenCard(): Component = text("[??]", DARK_GRAY)

    /** Renders a hand of cards, optionally hiding the first card. */
    fun renderHand(hand: Hand, hideFirst: Boolean = false): Component {
        if (hand.cards.isEmpty()) return text("(empty)", GRAY)

        return hand.cards
            .mapIndexed { index, card ->
                if (hideFirst && index == 0) renderHiddenCard() else renderCard(card)
            }
            .reduce { acc, component -> acc.append(text(" ")).append(component) }
    }

    /** Renders the current game state showing all hands. */
    fun renderGameState(session: GameSession, showDealerHand: Boolean = false): Component {
        val showDealer = showDealerHand || session.isFinished

        var message = Component.empty()
            .append(DIVIDER).append(newline())

        // Render all player hands (multiple if split)
        if (session.playerHands.size == 1) {
            message = message.append(renderHandSection("Your Hand", session.playerHand, session))
        } else {
            session.playerHands.forEachIndexed { index, hand ->
                val isActive = index == session.currentHandIndex && session.isPlayerTurn
                val label = "Hand ${index + 1}" + if (isActive) " (active)" else ""
                val labelColor = if (isActive) GREEN else YELLOW
                message = message.append(renderHandSectionWithColor(label, hand, labelColor))
            }
        }

        message = message.append(newline())

        // Render dealer's hand
        message = if (showDealer) {
            message.append(renderHandSection("Dealer's Hand", session.dealerHand, null))
        } else {
            message.append(text("Dealer shows:", YELLOW)).append(newline())
                .append(text("  ")).append(renderHand(session.dealerHand, hideFirst = true)).append(newline())
        }

        return message
    }

    private fun renderHandSection(label: String, hand: Hand, session: GameSession?): Component {
        var extra = ""
        if (hand.hasDoubledDown) extra += " [DOUBLED]"
        if (hand.hasSurrendered) extra += " [SURRENDERED]"
        if (hand.isSoft) extra += " (soft)"

        return text("$label ", YELLOW)
            .append(text("(${hand.value})", WHITE))
            .append(if (extra.isNotEmpty()) text(extra, GRAY) else Component.empty())
            .append(text(":", YELLOW))
            .append(newline())
            .append(text("  "))
            .append(renderHand(hand))
            .append(newline())
    }

    private fun renderHandSectionWithColor(label: String, hand: Hand, labelColor: NamedTextColor): Component {
        var extra = ""
        if (hand.hasDoubledDown) extra += " [DOUBLED]"
        if (hand.hasSurrendered) extra += " [SURRENDERED]"

        return text("$label ", labelColor)
            .append(text("(${hand.value})", WHITE))
            .append(if (extra.isNotEmpty()) text(extra, GRAY) else Component.empty())
            .append(text(":", labelColor))
            .append(newline())
            .append(text("  "))
            .append(renderHand(hand))
            .append(newline())
    }

    /** Renders clickable action buttons based on available actions. */
    fun renderActionButtons(session: GameSession): Component {
        var message = Component.empty().append(newline())

        val buttons = mutableListOf<Component>()

        // Basic actions
        if (session.canHit()) {
            buttons.add(createButton("[HIT]", GREEN, "/deal hit", "Draw another card"))
        }
        buttons.add(createButton("[STAND]", RED, "/deal stand", "End your turn"))

        // Advanced actions (only show if available)
        if (session.canDoubleDown()) {
            buttons.add(createButton("[DOUBLE]", GOLD, "/deal double", "Double bet, get one card"))
        }
        if (session.canSplit()) {
            buttons.add(createButton("[SPLIT]", AQUA, "/deal split", "Split pair into two hands"))
        }
        if (session.canSurrender()) {
            buttons.add(createButton("[SURRENDER]", GRAY, "/deal surrender", "Forfeit half your bet"))
        }

        // Join buttons with spacing
        message = message.append(text("  "))
        buttons.forEachIndexed { index, button ->
            if (index > 0) message = message.append(text(" "))
            message = message.append(button)
        }

        return message
            .append(newline())
            .append(DIVIDER)
    }

    /** Renders insurance prompt buttons. */
    fun renderInsurancePrompt(): Component {
        return Component.empty()
            .append(newline())
            .append(text("Dealer shows an Ace!", GOLD).decorate(TextDecoration.BOLD))
            .append(newline())
            .append(text("Would you like insurance?", YELLOW))
            .append(newline())
            .append(newline())
            .append(text("  "))
            .append(createButton("[YES - Take Insurance]", GREEN, "/deal insurance yes", "Bet on dealer having blackjack (pays 2:1)"))
            .append(text(" "))
            .append(createButton("[NO - Decline]", RED, "/deal insurance no", "Continue without insurance"))
            .append(newline())
            .append(DIVIDER)
    }

    /** Renders the game result with a Play Again button. */
    fun renderResult(result: GameResult): Component {
        val (message, color) = result.toDisplayInfo()

        return Component.empty()
            .append(newline())
            .append(text(">>> $message <<<", color).decorate(TextDecoration.BOLD))
            .append(newline())
            .append(DIVIDER)
            .append(newline())
            .append(createButton("[Play Again]", AQUA, "/deal start", "Start a new game"))
    }

    /** Renders results for multiple hands (after split). */
    fun renderMultiHandResults(session: GameSession): Component {
        var message = Component.empty().append(newline())

        session.handResults.forEachIndexed { index, handResult ->
            val (resultText, color) = handResult.result.toDisplayInfo()
            message = message
                .append(text("Hand ${index + 1}: ", YELLOW))
                .append(text(resultText, color))
                .append(newline())
        }

        return message
            .append(newline())
            .append(DIVIDER)
            .append(newline())
            .append(createButton("[Play Again]", AQUA, "/deal start", "Start a new game"))
    }

    private fun GameResult.toDisplayInfo(): Pair<String, NamedTextColor> = when (this) {
        GameResult.PLAYER_BLACKJACK -> "BLACKJACK! You win!" to GOLD
        GameResult.PLAYER_WIN -> "You win!" to GREEN
        GameResult.DEALER_BUST -> "Dealer busts! You win!" to GREEN
        GameResult.DEALER_WIN -> "Dealer wins!" to RED
        GameResult.PLAYER_BUST -> "Bust! You lose!" to RED
        GameResult.PUSH -> "Push! It's a tie!" to YELLOW
        GameResult.SURRENDERED -> "Surrendered (half bet returned)" to GRAY
    }

    /** Renders player statistics. */
    fun renderStats(stats: PlayerStats): Component {
        val winRate = stats.winRateFormatted

        return Component.empty()
            .append(DIVIDER).append(newline())
            .append(text("       Blackjack Stats", YELLOW).decorate(TextDecoration.BOLD)).append(newline())
            .append(DIVIDER).append(newline())
            .appendStat("Games Played", stats.gamesPlayed, AQUA)
            .appendStat("Wins", stats.wins, GREEN, " ($winRate)")
            .appendStat("Losses", stats.losses, RED)
            .appendStat("Pushes", stats.pushes, YELLOW)
            .appendStat("Surrenders", stats.surrenders, GRAY)
            .appendStat("Blackjacks", stats.blackjacks, GOLD)
            .appendStat("Current Streak", stats.currentWinStreak, LIGHT_PURPLE)
            .appendStat("Best Streak", stats.bestWinStreak, LIGHT_PURPLE)
            .append(DIVIDER)
    }

    private val PlayerStats.winRateFormatted: String
        get() = if (gamesPlayed > 0) "%.1f%%".format(wins.toDouble() / gamesPlayed * 100) else "N/A"

    private fun Component.appendStat(
        label: String,
        value: Int,
        valueColor: NamedTextColor,
        suffix: String = ""
    ): Component = this
        .append(text("  $label: ", WHITE))
        .append(text("$value", valueColor))
        .apply { if (suffix.isNotEmpty()) append(text(suffix, GRAY)) }
        .append(newline())

    private fun createButton(
        label: String,
        color: NamedTextColor,
        command: String,
        hoverText: String
    ): Component = text(label, color)
        .decorate(TextDecoration.BOLD)
        .clickEvent(ClickEvent.runCommand(command))
        .hoverEvent(HoverEvent.showText(text(hoverText, GRAY)))

    /** Sends the complete game display to a player. */
    fun sendGameDisplay(player: Player, session: GameSession) {
        player.sendMessage(renderGameState(session))
        when {
            session.isWaitingForInsurance -> player.sendMessage(renderInsurancePrompt())
            session.isPlayerTurn -> player.sendMessage(renderActionButtons(session))
            session.isFinished -> {
                if (session.handResults.size > 1) {
                    player.sendMessage(renderMultiHandResults(session))
                } else {
                    session.result?.let { player.sendMessage(renderResult(it)) }
                }
            }
        }
    }
}
