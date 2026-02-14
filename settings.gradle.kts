rootProject.name = "minecraft-server"

pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        maven("https://repo.papermc.io/repository/maven-public/")
        maven("https://repo.panda-lang.org/releases")
    }
}

include("plugins:example-plugin")
include("plugins:blackjack-plugin")
include("plugins:fart-plugin")
