package com.example.fart

import net.kyori.adventure.text.Component
import net.kyori.adventure.text.format.NamedTextColor

/**
 * Player-visible /fart lines. Colors match the old section-sign strings:
 * gold for the sender, yellow for everyone nearby.
 */
internal fun fartSelfMessage(): Component =
    Component.text("💨 *Fart noise* 💨", NamedTextColor.GOLD)

internal fun fartNearbyMessage(playerName: String): Component =
    Component.text("$playerName farted! 💨", NamedTextColor.YELLOW)

internal fun fartPlayersOnlyMessage(): Component =
    Component.text("Only players can use this command!")
