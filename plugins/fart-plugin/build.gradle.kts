plugins {
    kotlin("jvm")
    id("com.gradleup.shadow") version "8.3.5"
}

val paperApiVersion: String by project

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    // Paper API
    compileOnly("io.papermc.paper:paper-api:$paperApiVersion")

    // Kotlin stdlib (bundled by Paper, but declared for IDE support)
    compileOnly(kotlin("stdlib"))
}

tasks {
    jar {
        archiveClassifier.set("slim")
    }

    shadowJar {
        archiveClassifier.set("")
        minimize()
    }

    build {
        dependsOn(shadowJar)
    }

    // Copy built JAR to server plugins folder
    register<Copy>("deployToServer") {
        dependsOn(shadowJar)
        from(shadowJar.get().archiveFile)
        into(layout.projectDirectory.dir("../../server/plugins"))
    }

    processResources {
        val props = mapOf(
            "version" to version,
            "apiVersion" to paperApiVersion.split("-").first()
        )
        inputs.properties(props)
        filesMatching("plugin.yml") {
            expand(props)
        }
    }
}

kotlin {
    jvmToolchain(21)
}
