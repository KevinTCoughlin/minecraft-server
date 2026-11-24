package com.example.plugin

import net.kyori.adventure.text.Component

/**
 * Chat lines for the example commands. The prefix is included as written in
 * config, including any `&` codes, because the old string messages did not
 * translate those codes.
 */
internal fun helloMessage(prefix: String, message: String): Component =
    Component.text("$prefix $message")

internal fun pingMessage(milliseconds: Int): Component =
    Component.text("Pong! Your ping is ${milliseconds}ms")

internal fun consolePingMessage(): Component =
    Component.text("Pong! (Console has no ping)")
