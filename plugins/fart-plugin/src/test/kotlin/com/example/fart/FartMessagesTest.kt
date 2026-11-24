package com.example.fart

import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class FartMessagesTest {
    private val legacy = LegacyComponentSerializer.legacySection()

    @Test
    fun `self message keeps the gold section-sign text`() {
        assertEquals("§6💨 *Fart noise* 💨", legacy.serialize(fartSelfMessage()))
    }

    @Test
    fun `nearby message keeps the yellow section-sign text`() {
        assertEquals("§eSteve farted! 💨", legacy.serialize(fartNearbyMessage("Steve")))
    }

    @Test
    fun `console message stays plain`() {
        assertEquals(
            "Only players can use this command!",
            legacy.serialize(fartPlayersOnlyMessage())
        )
    }
}
