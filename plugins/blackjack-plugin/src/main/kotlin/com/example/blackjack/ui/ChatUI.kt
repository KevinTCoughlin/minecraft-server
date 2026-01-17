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

    /** Renders the current game state showing both hands. */
    fun renderGameState(session: GameSession, showDealerHand: Boolean = false): Component {
        val showDealer = showDealerHand || session.isFinished

        return Component.empty()
            .append(DIVIDER).append(newline())
            .append(renderHandSection("Your Hand", session.playerHand.value, session.playerHand))
            .append(newline())
            .append(
                if (showDealer) {
                    renderHandSection("Dealer's Hand", session.dealerHand.value, session.dealerHand)
                } else {
                    text("Dealer shows:", YELLOW).append(newline())
                        .append(text("  ")).append(renderHand(session.dealerHand, hideFirst = true)).append(newline())
                }
            )
    }

    private fun renderHandSection(label: String, value: Int, hand: Hand): Component =
        text("$label ", YELLOW)
            .append(text("($value)", WHITE))
            .append(text(":", YELLOW))
            .append(newline())
            .append(text("  "))
            .append(renderHand(hand))
            .append(newline())

    /** Renders clickable HIT and STAND buttons. */
    fun renderActionButtons(): Component {
        val hitButton = createButton("[HIT]", GREEN, "/bj hit", "Draw another card")
        val standButton = createButton("[STAND]", RED, "/bj stand", "End your turn")

        return Component.empty()
            .append(newline())
            .append(text("      "))
            .append(hitButton)
            .append(text("  "))
            .append(standButton)
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
            .append(createButton("[Play Again]", AQUA, "/bj start", "Start a new game"))
    }

    private fun GameResult.toDisplayInfo(): Pair<String, NamedTextColor> = when (this) {
        GameResult.PLAYER_BLACKJACK -> "BLACKJACK! You win!" to GOLD
        GameResult.PLAYER_WIN -> "You win!" to GREEN
        GameResult.DEALER_BUST -> "Dealer busts! You win!" to GREEN
        GameResult.DEALER_WIN -> "Dealer wins!" to RED
        GameResult.PLAYER_BUST -> "Bust! You lose!" to RED
        GameResult.PUSH -> "Push! It's a tie!" to YELLOW
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
            session.isPlayerTurn -> player.sendMessage(renderActionButtons())
            session.isFinished -> session.result?.let { player.sendMessage(renderResult(it)) }
        }
    }
}
