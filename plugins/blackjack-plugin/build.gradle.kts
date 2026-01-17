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

    // Kotlin stdlib - include in JAR for plugin classloader
    implementation(kotlin("stdlib"))

    // Testing
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}

tasks {
    jar {
        archiveClassifier.set("slim")
    }

    shadowJar {
        archiveClassifier.set("")
        // Relocate Kotlin to avoid conflicts with other plugins
        relocate("kotlin", "com.example.blackjack.kotlin")
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
        val apiVer = paperApiVersion.substringBefore("-")
        val props = mapOf(
            "version" to version,
            "apiVersion" to apiVer
        )
        inputs.properties(props)
        filteringCharset = "UTF-8"
        filesMatching("plugin.yml") {
            expand(props)
        }
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions {
        jvmTarget = "21"
    }
}
