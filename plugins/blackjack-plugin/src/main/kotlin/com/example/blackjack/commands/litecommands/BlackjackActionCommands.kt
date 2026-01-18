package com.example.blackjack.commands.litecommands

import com.example.blackjack.BlackjackPlugin
import com.example.blackjack.ui.ChatUI
import dev.rollczi.litecommands.annotations.command.Command
import dev.rollczi.litecommands.annotations.context.Context
import dev.rollczi.litecommands.annotations.execute.Execute
import net.kyori.adventure.text.Component.text
import net.kyori.adventure.text.format.NamedTextColor.*
import org.bukkit.entity.Player

/**
 * Handles game action subcommands: hit, stand, double, split, surrender
 */
@Command(name = "bj")
class BlackjackActionCommands(plugin: BlackjackPlugin) : BaseBlackjackCommand(plugin) {

    @Execute(name = "hit")
    fun hit(@Context player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first! Use /bj insurance yes or /bj insurance no")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn to hit!")
            return
        }

        if (!session.canHit()) {
            player.sendError("You can't hit right now (split aces only get one card).")
            return
        }

        session.hit()
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    @Execute(name = "stand")
    fun stand(@Context player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first! Use /bj insurance yes or /bj insurance no")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        session.stand()
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    @Execute(name = "double")
    fun doubleDown(@Context player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canDoubleDown()) {
            player.sendError("You can't double down right now. Double is only available on your first two cards.")
            return
        }

        session.doubleDown()
        player.sendMessage(text("Doubled down! Drawing one card...", GOLD))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    @Execute(name = "split")
    fun split(@Context player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canSplit()) {
            player.sendError("You can't split right now. Split is only available when you have a pair.")
            return
        }

        session.split()
        player.sendMessage(text("Split! Now playing hand ${session.getCurrentHandNumber()} of ${session.getHandCount()}", AQUA))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }

    @Execute(name = "surrender")
    fun surrender(@Context player: Player) {
        val session = gameManager[player.uniqueId] ?: run {
            player.sendError("You don't have an active game! Use /bj to start one.")
            return
        }

        if (session.isWaitingForInsurance) {
            player.sendError("You must decide on insurance first!")
            return
        }

        if (!session.isPlayerTurn) {
            player.sendError("It's not your turn!")
            return
        }

        if (!session.canSurrender()) {
            player.sendError("You can't surrender right now. Surrender is only available on your first two cards.")
            return
        }

        session.surrender()
        player.sendMessage(text("Surrendered. Half your bet has been returned.", GRAY))
        ChatUI.sendGameDisplay(player, session)

        if (session.isFinished) {
            gameManager.endGame(player.uniqueId)?.let { handleGameEnd(player, it) }
        }
    }
}
