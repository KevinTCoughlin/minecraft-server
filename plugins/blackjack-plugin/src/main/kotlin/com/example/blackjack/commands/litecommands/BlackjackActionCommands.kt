package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.*
import org.bukkit.entity.Player

/**
 * Handles game action subcommands: hit, stand, double, split, surrender
 */
@Command(name = "deal")
class BlackjackActionCommands(plugin: BlackjackPlugin) : BaseBlackjackCommand(plugin) {

    @Execute(name = "hit")
    fun hit(@Context player: Player) = player.withValidSession { session ->
        if (!session.canHit()) {
            player.sendError("You can't hit right now (split aces only get one card).")
            return
        }
        session.hit()
        finishAction(player, session)
    }

    @Execute(name = "stand")
    fun stand(@Context player: Player) = player.withValidSession { session ->
        session.stand()
        finishAction(player, session)
    }

    @Execute(name = "double")
    fun doubleDown(@Context player: Player) = player.withValidSession { session ->
        if (!session.canDoubleDown()) {
            player.sendError("You can't double down right now. Double is only available on your first two cards.")
            return
        }
        session.doubleDown()
        player.sendMessage(text("Doubled down! Drawing one card...", GOLD))
        finishAction(player, session)
    }

    @Execute(name = "split")
    fun split(@Context player: Player) = player.withValidSession { session ->
        if (!session.canSplit()) {
            player.sendError("You can't split right now. Split is only available when you have a pair.")
            return
        }
        session.split()
        player.sendMessage(text("Split! Now playing hand ${session.getCurrentHandNumber()} of ${session.getHandCount()}", AQUA))
        finishAction(player, session)
    }

    @Execute(name = "surrender")
    fun surrender(@Context player: Player) = player.withValidSession { session ->
        if (!session.canSurrender()) {
            player.sendError("You can't surrender right now. Surrender is only available on your first two cards.")
            return
        }
        session.surrender()
        player.sendMessage(text("Surrendered. Half your bet has been returned.", GRAY))
        finishAction(player, session)
    }
}
