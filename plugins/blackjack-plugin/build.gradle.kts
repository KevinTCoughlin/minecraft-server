plugins {
    id("paper-plugin")
    kotlin("plugin.serialization")
}

dependencies {
    compileOnly(libs.paper.api)

    // Kotlin stdlib - include in JAR for plugin classloader
    implementation(libs.kotlin.stdlib)

    // kotlinx.serialization + kaml for type-safe YAML config
    implementation(libs.kotlinx.serialization.core)
    implementation(libs.kaml)

    // LiteCommands - Modern command framework
    implementation(libs.litecommands.bukkit)
    implementation(libs.litecommands.adventure)

    // Testing
    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
}

tasks.shadowJar {
    // Relocate Kotlin to avoid conflicts with other plugins
    relocate("kotlin", "com.example.blackjack.kotlin")
    // Relocate LiteCommands to avoid conflicts with other plugins
    relocate("dev.rollczi.litecommands", "com.example.blackjack.litecommands")
    // Relocate serialization libraries
    relocate("kotlinx.serialization", "com.example.blackjack.kotlinx.serialization")
    relocate("com.charleskorn.kaml", "com.example.blackjack.kaml")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    compilerOptions {
        // Enable parameter names at runtime for LiteCommands
        javaParameters.set(true)
    }
}

tasks.withType<JavaCompile> {
    // Enable parameter names at runtime for LiteCommands
    options.compilerArgs.add("-parameters")
}
