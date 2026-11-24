package com.example.plugin

import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class ChatMessagesTest {
    private val legacy = LegacyComponentSerializer.legacySection()

    @Test
    fun `hello keeps the configured prefix text`() {
        assertEquals(
            "&6[Example]&r Hello, Steve!",
            legacy.serialize(helloMessage("&6[Example]&r", "Hello, Steve!"))
        )
    }

    @Test
    fun `ping keeps the plain millisecond text`() {
        assertEquals("Pong! Your ping is 42ms", legacy.serialize(pingMessage(42)))
    }

    @Test
    fun `console ping stays plain`() {
        assertEquals("Pong! (Console has no ping)", legacy.serialize(consolePingMessage()))
    }
}
