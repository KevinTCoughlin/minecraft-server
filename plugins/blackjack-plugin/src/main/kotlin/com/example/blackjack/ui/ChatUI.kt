package com.example.blackjack.ui

import com.example.blackjack.game.*
import net.kyori.adventure.text.Component
import net.kyori.adventure.text.event.ClickEvent
import net.kyori.adventure.text.event.HoverEvent
import net.kyori.adventure.text.format.NamedTextColor
import net.kyori.adventure.text.format.TextDecoration
import org.bukkit.entity.Player

object ChatUI {

    fun renderCard(card: Card): Component {
        val color = if (card.suit.isRed) NamedTextColor.RED else NamedTextColor.WHITE
        return Component.text("[${card.display}]", color)
    }

    fun renderHiddenCard(): Component {
        return Component.text("[??]", NamedTextColor.DARK_GRAY)
    }

    fun renderHand(hand: Hand, hideFirst: Boolean = false): Component {
        val cards = hand.getCards()
        if (cards.isEmpty()) {
            return Component.text("(empty)", NamedTextColor.GRAY)
        }

        var result = Component.empty()
        cards.forEachIndexed { index, card ->
            if (index > 0) {
                result = result.append(Component.text(" "))
            }
            result = if (hideFirst && index == 0) {
                result.append(renderHiddenCard())
            } else {
                result.append(renderCard(card))
            }
        }
        return result
    }

    fun renderGameState(session: GameSession, showDealerHand: Boolean = false): Component {
        val playerValue = session.playerHand.getValue()
        val showDealer = showDealerHand || session.isFinished()

        var message = Component.empty()

        // Header
        message = message.append(
            Component.text("═══════════════════════════════", NamedTextColor.GOLD)
        ).append(Component.newline())

        // Player's hand
        message = message.append(
            Component.text("Your Hand ", NamedTextColor.YELLOW)
        ).append(
            Component.text("($playerValue)", NamedTextColor.WHITE)
        ).append(
            Component.text(":", NamedTextColor.YELLOW)
        ).append(Component.newline())

        message = message.append(Component.text("  "))
            .append(renderHand(session.playerHand))
            .append(Component.newline())

        // Dealer's hand
        message = message.append(Component.newline())
        if (showDealer) {
            val dealerValue = session.dealerHand.getValue()
            message = message.append(
                Component.text("Dealer's Hand ", NamedTextColor.YELLOW)
            ).append(
                Component.text("($dealerValue)", NamedTextColor.WHITE)
            ).append(
                Component.text(":", NamedTextColor.YELLOW)
            ).append(Component.newline())
            message = message.append(Component.text("  "))
                .append(renderHand(session.dealerHand))
                .append(Component.newline())
        } else {
            message = message.append(
                Component.text("Dealer shows:", NamedTextColor.YELLOW)
            ).append(Component.newline())
            message = message.append(Component.text("  "))
                .append(renderHand(session.dealerHand, hideFirst = true))
                .append(Component.newline())
        }

        return message
    }

    fun renderActionButtons(): Component {
        val hitButton = Component.text("[HIT]", NamedTextColor.GREEN)
            .decorate(TextDecoration.BOLD)
            .clickEvent(ClickEvent.runCommand("/bj hit"))
            .hoverEvent(HoverEvent.showText(Component.text("Draw another card", NamedTextColor.GRAY)))

        val standButton = Component.text("[STAND]", NamedTextColor.RED)
            .decorate(TextDecoration.BOLD)
            .clickEvent(ClickEvent.runCommand("/bj stand"))
            .hoverEvent(HoverEvent.showText(Component.text("End your turn", NamedTextColor.GRAY)))

        return Component.empty()
            .append(Component.newline())
            .append(Component.text("      "))
            .append(hitButton)
            .append(Component.text("  "))
            .append(standButton)
            .append(Component.newline())
            .append(Component.text("═══════════════════════════════", NamedTextColor.GOLD))
    }

    fun renderResult(result: GameResult): Component {
        val (message, color) = when (result) {
            GameResult.PLAYER_BLACKJACK -> "BLACKJACK! You win!" to NamedTextColor.GOLD
            GameResult.PLAYER_WIN -> "You win!" to NamedTextColor.GREEN
            GameResult.DEALER_BUST -> "Dealer busts! You win!" to NamedTextColor.GREEN
            GameResult.DEALER_WIN -> "Dealer wins!" to NamedTextColor.RED
            GameResult.PLAYER_BUST -> "Bust! You lose!" to NamedTextColor.RED
            GameResult.PUSH -> "Push! It's a tie!" to NamedTextColor.YELLOW
        }

        return Component.empty()
            .append(Component.newline())
            .append(Component.text(">>> $message <<<", color).decorate(TextDecoration.BOLD))
            .append(Component.newline())
            .append(Component.text("═══════════════════════════════", NamedTextColor.GOLD))
            .append(Component.newline())
            .append(
                Component.text("[Play Again]", NamedTextColor.AQUA)
                    .decorate(TextDecoration.BOLD)
                    .clickEvent(ClickEvent.runCommand("/bj start"))
                    .hoverEvent(HoverEvent.showText(Component.text("Start a new game", NamedTextColor.GRAY)))
            )
    }

    fun renderStats(stats: PlayerStats): Component {
        val winRate = if (stats.gamesPlayed > 0) {
            "%.1f%%".format((stats.wins.toDouble() / stats.gamesPlayed) * 100)
        } else {
            "N/A"
        }

        return Component.empty()
            .append(Component.text("═══════════════════════════════", NamedTextColor.GOLD))
            .append(Component.newline())
            .append(Component.text("       Blackjack Stats", NamedTextColor.YELLOW).decorate(TextDecoration.BOLD))
            .append(Component.newline())
            .append(Component.text("═══════════════════════════════", NamedTextColor.GOLD))
            .append(Component.newline())
            .append(Component.text("  Games Played: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.gamesPlayed}", NamedTextColor.AQUA))
            .append(Component.newline())
            .append(Component.text("  Wins: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.wins}", NamedTextColor.GREEN))
            .append(Component.text(" ($winRate)", NamedTextColor.GRAY))
            .append(Component.newline())
            .append(Component.text("  Losses: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.losses}", NamedTextColor.RED))
            .append(Component.newline())
            .append(Component.text("  Pushes: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.pushes}", NamedTextColor.YELLOW))
            .append(Component.newline())
            .append(Component.text("  Blackjacks: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.blackjacks}", NamedTextColor.GOLD))
            .append(Component.newline())
            .append(Component.text("  Current Streak: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.currentWinStreak}", NamedTextColor.LIGHT_PURPLE))
            .append(Component.newline())
            .append(Component.text("  Best Streak: ", NamedTextColor.WHITE))
            .append(Component.text("${stats.bestWinStreak}", NamedTextColor.LIGHT_PURPLE))
            .append(Component.newline())
            .append(Component.text("═══════════════════════════════", NamedTextColor.GOLD))
    }

    fun sendGameDisplay(player: Player, session: GameSession) {
        player.sendMessage(renderGameState(session))
        if (session.isPlayerTurn()) {
            player.sendMessage(renderActionButtons())
        } else if (session.isFinished()) {
            session.result?.let { result ->
                player.sendMessage(renderResult(result))
            }
        }
    }
}
