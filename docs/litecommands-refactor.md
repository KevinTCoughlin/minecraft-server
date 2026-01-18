# Refactoring Blackjack Plugin with LiteCommands

A comprehensive guide to modernizing Minecraft plugin commands using the LiteCommands framework

---

## Table of Contents

1. [Introduction](#introduction)
2. [What is LiteCommands?](#what-is-litecommands)
3. [Why Refactor?](#why-refactor)
4. [Before: Traditional Bukkit Commands](#before-traditional-bukkit-commands)
5. [After: Modern LiteCommands](#after-modern-litecommands)
6. [Step-by-Step Refactoring Guide](#step-by-step-refactoring-guide)
7. [Best Practices & Patterns](#best-practices--patterns)
8. [Testing the Implementation](#testing-the-implementation)
9. [Conclusion](#conclusion)

---

## Introduction

Welcome! In this guide, we'll walk through refactoring a Minecraft Blackjack plugin from traditional Bukkit command handling to the modern, annotation-based LiteCommands framework. This guide is designed for developers with beginner to intermediate Java/Kotlin experience who want to adopt modern best practices in their Minecraft plugin development.

By the end of this guide, you'll understand:
- The benefits of using LiteCommands over traditional command handlers
- How to structure commands using annotations
- Modern patterns for command organization and separation of concerns
- How to leverage Kotlin features with LiteCommands

---

## What is LiteCommands?

[LiteCommands](https://github.com/Rollczi/LiteCommands) is a powerful, annotation-based command framework for Minecraft platforms (Bukkit, Paper, Velocity, BungeeCord, and more). Created by Rollczi, it provides a modern, declarative approach to command creation that reduces boilerplate and improves code maintainability.

### Key Features

- **Annotation-Driven**: Define commands using `@Command`, `@Execute`, `@Arg`, and other intuitive annotations
- **Type Safety**: Automatic argument parsing with type safety
- **Async Support**: Built-in support for asynchronous command execution
- **Context Injection**: Direct injection of platform objects like `Player`, `World`, etc.
- **Auto-Completion**: Automatic tab completion generation
- **Kotlin-Friendly**: First-class support for Kotlin idioms and features
- **Extensible**: Easy to add custom argument types and validators

---

## Why Refactor?

### Problems with Traditional Bukkit Commands

The traditional Bukkit command pattern has several limitations:

1. **Boilerplate Code**: Lots of manual argument parsing and validation
2. **Poor Separation of Concerns**: Command logic mixed with argument handling
3. **Limited Type Safety**: Arguments are strings that need manual conversion
4. **Manual Tab Completion**: Tab completion logic is separate and tedious
5. **Difficult to Test**: Tightly coupled to Bukkit infrastructure
6. **Scalability Issues**: Large command classes become unwieldy

### Benefits of LiteCommands

1. **Declarative Syntax**: Commands are self-documenting through annotations
2. **Automatic Parsing**: Framework handles argument conversion and validation
3. **Better Organization**: Natural separation of command handlers
4. **Type Safety**: Compile-time checking of argument types
5. **Less Code**: Significantly reduces boilerplate
6. **Modern Patterns**: Aligns with contemporary software development practices

---

## Before: Traditional Bukkit Commands

Let's look at our original blackjack command implementation:

```kotlin
class BlackjackCommand(private val plugin: BlackjackPlugin) : CommandExecutor, TabCompleter {

    override fun onCommand(
        sender: CommandSender,
        command: Command,
        label: String,
        args: Array<out String>
    ): Boolean {
        val player = sender as? Player ?: run {
            sender.sendMessage(text("This command can only be used by players!", RED))
            return true
        }

        when (args.getOrNull(0)?.lowercase() ?: "start") {
            "start" -> handleStart(player)
            "hit" -> handleHit(player)
            "stand" -> handleStand(player)
            "double" -> handleDouble(player)
            "split" -> handleSplit(player)
            "surrender" -> handleSurrender(player)
            "insurance" -> handleInsurance(player, args.getOrNull(1))
            "stats" -> handleStats(player)
            "rules" -> handleRules(player)
            else -> player.sendError("Unknown subcommand...")
        }

        return true
    }

    override fun onTabComplete(
        sender: CommandSender,
        command: Command,
        alias: String,
        args: Array<out String>
    ): List<String> = when {
        args.size == 1 -> SUBCOMMANDS.filter { it.startsWith(args[0], ignoreCase = true) }
        args.size == 2 && args[0].equals("insurance", ignoreCase = true) ->
            INSURANCE_OPTIONS.filter { it.startsWith(args[1], ignoreCase = true) }
        else -> emptyList()
    }
}
```

### Issues with This Approach

1. **Single Massive Class**: All command logic in one file (340+ lines)
2. **Manual Routing**: We have to manually parse and route to handler methods
3. **Manual Player Check**: Every command needs the same player validation
4. **Manual Argument Parsing**: We're manually extracting and validating `args[1]`
5. **Separate Tab Completion**: Tab completion logic is in a different method
6. **Hard to Test**: Can't easily unit test individual command handlers

---

## After: Modern LiteCommands

With LiteCommands, we split our monolithic command class into focused, single-responsibility classes:

### 1. Base Command Handler

```kotlin
@Command(name = "bj", aliases = ["blackjack"])
@Permission("blackjack.play")
class BlackjackBaseCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun start(@Context player: Player) {
        // Start game logic
        if (player.uniqueId in gameManager) {
            gameManager.endGame(player.uniqueId)
        }

        val session = gameManager.startGame(player.uniqueId)
        // ... rest of logic
    }
}
```

### 2. Action Commands Handler

```kotlin
@Command(name = "bj")
class BlackjackActionCommands(private val plugin: BlackjackPlugin) {

    @Execute(name = "hit")
    fun hit(@Context player: Player) {
        // Hit logic
    }

    @Execute(name = "stand")
    fun stand(@Context player: Player) {
        // Stand logic
    }

    @Execute(name = "double")
    fun doubleDown(@Context player: Player) {
        // Double down logic
    }

    @Execute(name = "split")
    fun split(@Context player: Player) {
        // Split logic
    }

    @Execute(name = "surrender")
    fun surrender(@Context player: Player) {
        // Surrender logic
    }
}
```

### 3. Insurance Command Handler

```kotlin
@Command(name = "bj insurance")
class BlackjackInsuranceCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun insurance(@Context player: Player, @Arg decision: String) {
        // Insurance decision logic
        when (decision.lowercase()) {
            "yes", "y" -> session.takeInsurance()
            "no", "n" -> session.declineInsurance()
            else -> player.sendError("Usage: /bj insurance yes or no")
        }
    }
}
```

### 4. Stats & Rules Handlers

```kotlin
@Command(name = "bj stats")
class BlackjackStatsCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun stats(@Context player: Player) {
        player.sendMessage(ChatUI.renderStats(plugin.gameManager.getStats(player.uniqueId)))
    }
}

@Command(name = "bj rules")
class BlackjackRulesCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun rules(@Context player: Player) {
        // Display rules
    }
}
```

### Key Improvements

1. **Focused Classes**: Each command handler has a single responsibility
2. **No Manual Routing**: Annotations handle command routing
3. **Automatic Context**: `@Context player: Player` injects the player automatically
4. **Type-Safe Arguments**: `@Arg decision: String` is automatically parsed
5. **Self-Documenting**: Command structure is clear from annotations
6. **Easier Testing**: Each handler can be tested independently

---

## Step-by-Step Refactoring Guide

### Step 1: Add LiteCommands Dependencies

First, update your `build.gradle.kts`:

```kotlin
repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
    maven("https://repo.panda-lang.org/releases")  // Add this
}

dependencies {
    // ... existing dependencies

    // Add LiteCommands
    implementation("dev.rollczi:litecommands-bukkit:3.10.9")
    implementation("dev.rollczi:litecommands-adventure:3.10.9")
}
```

### Step 2: Enable Parameter Names

LiteCommands works best with parameter names enabled at compile time:

```kotlin
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions {
        jvmTarget = "21"
        javaParameters = true  // Add this
    }
}

tasks.withType<JavaCompile> {
    options.compilerArgs.add("-parameters")  // Add this for Java
}
```

### Step 3: Relocate Dependencies

To avoid conflicts with other plugins, relocate LiteCommands in your shadow JAR:

```kotlin
shadowJar {
    archiveClassifier.set("")
    relocate("kotlin", "com.example.blackjack.kotlin")
    relocate("dev.rollczi.litecommands", "com.example.blackjack.litecommands")
}
```

### Step 4: Create Command Classes

Create a new package for your LiteCommands handlers:

```
src/main/kotlin/com/example/blackjack/commands/litecommands/
├── BlackjackBaseCommand.kt
├── BlackjackActionCommands.kt
├── BlackjackInsuranceCommand.kt
├── BlackjackStatsCommand.kt
└── BlackjackRulesCommand.kt
```

### Step 5: Implement Base Command

Start with your main command:

```kotlin
@Command(name = "bj", aliases = ["blackjack"])
@Permission("blackjack.play")
class BlackjackBaseCommand(private val plugin: BlackjackPlugin) {

    private val gameManager: GameManager
        get() = plugin.gameManager

    @Execute
    fun start(@Context player: Player) {
        // Your command logic here
    }
}
```

**Key Points:**
- `@Command` defines the command name and aliases
- `@Permission` sets the required permission
- `@Execute` marks the method that runs when the command is called
- `@Context` injects the command sender as a Player

### Step 6: Implement Subcommands

For subcommands, use `@Execute(name = "subcommand")`:

```kotlin
@Command(name = "bj")
class BlackjackActionCommands(private val plugin: BlackjackPlugin) {

    @Execute(name = "hit")
    fun hit(@Context player: Player) {
        // Hit logic
    }

    @Execute(name = "stand")
    fun stand(@Context player: Player) {
        // Stand logic
    }
}
```

### Step 7: Handle Arguments

For commands with arguments, use `@Arg`:

```kotlin
@Command(name = "bj insurance")
class BlackjackInsuranceCommand(private val plugin: BlackjackPlugin) {

    @Execute
    fun insurance(@Context player: Player, @Arg decision: String) {
        // decision is automatically parsed from command arguments
    }
}
```

### Step 8: Register Commands

Update your plugin's `onEnable()` method:

```kotlin
class BlackjackPlugin : JavaPlugin() {

    private lateinit var liteCommands: LiteCommands<CommandSender>

    override fun onEnable() {
        // ... other initialization

        registerCommands()
    }

    override fun onDisable() {
        if (::liteCommands.isInitialized) {
            liteCommands.unregister()
        }
    }

    private fun registerCommands() {
        liteCommands = LiteBukkitFactory.builder(this)
            .commands(
                BlackjackBaseCommand(this),
                BlackjackActionCommands(this),
                BlackjackInsuranceCommand(this),
                BlackjackStatsCommand(this),
                BlackjackRulesCommand(this)
            )
            .build()
    }
}
```

### Step 9: Remove Old Command Registration

You can now remove the old command registration from `plugin.yml` and the old command handler class.

---

## Best Practices & Patterns

### 1. Single Responsibility Principle

Each command class should handle a logical group of related commands:

```kotlin
// ✅ Good: Focused on game actions
@Command(name = "bj")
class BlackjackActionCommands {
    @Execute(name = "hit") fun hit()
    @Execute(name = "stand") fun stand()
    @Execute(name = "double") fun doubleDown()
}

// ❌ Bad: Too many unrelated commands in one class
@Command(name = "bj")
class BlackjackCommands {
    @Execute(name = "hit") fun hit()
    @Execute(name = "stats") fun stats()
    @Execute(name = "admin") fun admin()
}
```

### 2. Dependency Injection

Pass dependencies through constructors rather than accessing them statically:

```kotlin
// ✅ Good: Dependencies injected
class BlackjackBaseCommand(private val plugin: BlackjackPlugin) {
    private val gameManager get() = plugin.gameManager
}

// ❌ Bad: Accessing singleton
class BlackjackBaseCommand {
    private val plugin = BlackjackPlugin.instance  // Anti-pattern
}
```

### 3. Error Handling

Create extension functions for common error patterns:

```kotlin
private fun Player.sendError(message: String) {
    sendMessage(text(message, RED))
}

// Usage
player.sendError("You don't have an active game!")
```

### 4. Validation Before Business Logic

Always validate state before executing business logic:

```kotlin
@Execute(name = "hit")
fun hit(@Context player: Player) {
    // Validate session exists
    val session = gameManager[player.uniqueId] ?: run {
        player.sendError("You don't have an active game!")
        return
    }

    // Validate it's player's turn
    if (!session.isPlayerTurn) {
        player.sendError("It's not your turn!")
        return
    }

    // Execute business logic
    session.hit()
    ChatUI.sendGameDisplay(player, session)
}
```

### 5. Reusable Helper Methods

Extract common patterns into helper methods:

```kotlin
abstract class BaseBlackjackCommand(protected val plugin: BlackjackPlugin) {

    protected val gameManager get() = plugin.gameManager

    protected fun handleGameEnd(player: Player, endResult: GameManager.GameEndResult) {
        // Common game end logic
    }

    protected fun Player.sendError(message: String) {
        sendMessage(text(message, RED))
    }
}

// Then extend in your commands
class BlackjackActionCommands(plugin: BlackjackPlugin) : BaseBlackjackCommand(plugin)
```

### 6. Use Kotlin Features

Leverage Kotlin's features for cleaner code:

```kotlin
// Scope functions
val session = gameManager[player.uniqueId] ?: run {
    player.sendError("No active game!")
    return
}

// Extension functions
private fun Player.sendError(message: String) =
    sendMessage(text(message, RED))

// When expressions
when (decision.lowercase()) {
    "yes", "y" -> session.takeInsurance()
    "no", "n" -> session.declineInsurance()
    else -> player.sendError("Invalid choice")
}

// Property delegation
private val gameManager: GameManager
    get() = plugin.gameManager
```

### 7. Command Naming Conventions

Use clear, consistent naming:

```kotlin
// ✅ Good: Clear, descriptive names
@Command(name = "bj")
class BlackjackActionCommands {
    @Execute(name = "hit") fun hit()
    @Execute(name = "stand") fun stand()
}

// ❌ Bad: Unclear, abbreviated names
@Command(name = "bj")
class BJAct {
    @Execute(name = "h") fun h()
    @Execute(name = "s") fun s()
}
```

### 8. Async Operations

For long-running operations, use `@Async`:

```kotlin
@Command(name = "bj stats")
class BlackjackStatsCommand(private val plugin: BlackjackPlugin) {

    @Execute
    @Async  // Run this command asynchronously
    fun stats(@Context player: Player) {
        // Potentially slow database operation
        val stats = database.loadStats(player.uniqueId)
        player.sendMessage(ChatUI.renderStats(stats))
    }
}
```

---

## Testing the Implementation

### Manual Testing Checklist

1. **Basic Command**: `/bj` - Start a game
2. **Game Actions**: `/bj hit`, `/bj stand`, `/bj double`, `/bj split`
3. **Insurance**: `/bj insurance yes`, `/bj insurance no`
4. **Info Commands**: `/bj stats`, `/bj rules`
5. **Tab Completion**: Test auto-completion for all commands
6. **Permissions**: Test without `blackjack.play` permission
7. **Edge Cases**: Test commands without an active game

### Unit Testing Example

With LiteCommands, testing is easier because commands are decoupled:

```kotlin
class BlackjackBaseCommandTest {

    private lateinit var plugin: BlackjackPlugin
    private lateinit var player: Player
    private lateinit var command: BlackjackBaseCommand

    @BeforeEach
    fun setup() {
        plugin = mock()
        player = mock()
        command = BlackjackBaseCommand(plugin)
    }

    @Test
    fun `start should create new game session`() {
        // Given
        val gameManager = mock<GameManager>()
        whenever(plugin.gameManager).thenReturn(gameManager)

        // When
        command.start(player)

        // Then
        verify(gameManager).startGame(player.uniqueId)
    }
}
```

---

## Conclusion

### What We Accomplished

In this refactoring, we:

1. ✅ Migrated from traditional Bukkit commands to LiteCommands
2. ✅ Reduced code complexity by splitting into focused classes
3. ✅ Eliminated manual argument parsing and validation
4. ✅ Improved code maintainability and testability
5. ✅ Adopted modern patterns and best practices
6. ✅ Made the codebase more Kotlin-idiomatic

### Results

**Before**: 1 monolithic class with 340+ lines  
**After**: 5 focused classes averaging 50-150 lines each

**Benefits**:
- **Reduced Complexity**: Each class has a single, clear purpose
- **Better Maintainability**: Changes are localized to specific handlers
- **Improved Testability**: Individual command handlers can be unit tested
- **Enhanced Readability**: Annotations make command structure self-documenting
- **Type Safety**: Compile-time checking prevents runtime errors
- **Less Boilerplate**: Framework handles repetitive tasks

### Next Steps

Now that you understand LiteCommands, consider:

1. **Advanced Features**: Explore optional arguments `@OptionalArg`, flags `@Flag`, and joiners `@Join`
2. **Custom Validators**: Create custom validation annotations for your domain
3. **Argument Types**: Register custom argument parsers for complex types
4. **Context Providers**: Create custom context providers for your application objects
5. **IntelliJ Plugin**: Install the [LiteCommands IntelliJ Plugin](https://github.com/LiteDevelopers/LiteCommands-IntelliJPlugin) for better IDE support

### Resources

- [LiteCommands GitHub](https://github.com/Rollczi/LiteCommands)
- [Official Documentation](https://docs.rollczi.dev/)
- [Example Plugins](https://github.com/Rollczi/LiteCommands/tree/master/examples)
- [Discord Community](https://discord.gg/6cUhkj6uZJ)

---

## Appendix: Complete Code Examples

### Plugin Main Class

```kotlin
class BlackjackPlugin : JavaPlugin() {

    lateinit var gameManager: GameManager
        private set

    lateinit var announcementManager: AnnouncementManager
        private set

    private lateinit var liteCommands: LiteCommands<CommandSender>

    override fun onEnable() {
        saveDefaultConfig()

        val gameConfig = loadGameConfig()
        gameManager = GameManager(gameConfig)
        announcementManager = AnnouncementManager(this)

        registerCommands()
        registerListeners()

        logger.info("${pluginMeta.name} v${pluginMeta.version} enabled!")
    }

    override fun onDisable() {
        if (::liteCommands.isInitialized) {
            liteCommands.unregister()
        }
        logger.info("${pluginMeta.name} disabled!")
    }

    private fun registerCommands() {
        liteCommands = LiteBukkitFactory.builder(this)
            .commands(
                BlackjackBaseCommand(this),
                BlackjackActionCommands(this),
                BlackjackInsuranceCommand(this),
                BlackjackStatsCommand(this),
                BlackjackRulesCommand(this)
            )
            .build()

        logger.info("LiteCommands initialized with 5 command handlers")
    }

    private fun registerListeners() {
        server.pluginManager.registerEvents(PlayerJoinListener(this), this)
    }

    private fun loadGameConfig(): GameConfig {
        // Config loading logic...
    }
}
```

### Build Configuration

```kotlin
plugins {
    kotlin("jvm")
    id("com.gradleup.shadow") version "8.3.5"
}

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
    maven("https://repo.panda-lang.org/releases")
}

dependencies {
    compileOnly("io.papermc.paper:paper-api:1.21.4-R0.1-SNAPSHOT")
    implementation(kotlin("stdlib"))
    implementation("dev.rollczi:litecommands-bukkit:3.10.9")
    implementation("dev.rollczi:litecommands-adventure:3.10.9")

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
}

tasks.withType<KotlinCompile> {
    kotlinOptions {
        jvmTarget = "21"
        javaParameters = true
    }
}

tasks.shadowJar {
    relocate("kotlin", "com.example.blackjack.kotlin")
    relocate("dev.rollczi.litecommands", "com.example.blackjack.litecommands")
}
```

---

**Author**: Generated as part of the Blackjack Plugin Refactoring Project  
**Date**: January 2026  
**Framework Version**: LiteCommands 3.10.9  
**Minecraft Version**: 1.21.4 (Paper)

---

*Happy coding! If you have questions or suggestions, feel free to open an issue or join the LiteCommands Discord community.*
