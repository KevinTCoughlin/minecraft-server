import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm")
    id("com.gradleup.shadow")
}

// Paper 26.3 plugins are built and run on Java 25. Java 21 cannot load this API.
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
        vendor.set(JvmVendorSpec.ADOPTIUM)
    }
}

kotlin {
    jvmToolchain(25)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_25)
        // Fail the build on Kotlin warnings, including the extra diagnostics
        // (redundant modifiers, unused values, and similar) so new code cannot
        // land with them. Nullness follows JSR-305 and JSpecify as strict so
        // Paper's annotated API is not treated as a platform type.
        allWarningsAsErrors.set(true)
        extraWarnings.set(true)
        freeCompilerArgs.addAll(
            "-Xjsr305=strict",
            "-Xjspecify-annotations=strict",
            "-Xconsistent-data-class-copy-visibility",
        )
    }
}

tasks {
    jar {
        archiveClassifier.set("slim")
    }

    shadowJar {
        archiveClassifier.set("")
        duplicatesStrategy = DuplicatesStrategy.WARN
        minimize()
    }

    build {
        dependsOn(shadowJar)
    }

    register<Copy>("deployToServer") {
        dependsOn(shadowJar)
        from(shadowJar.get().archiveFile)
        into(layout.projectDirectory.dir("../../server/plugins"))
    }

    processResources {
        val minecraftVersion = project.property("minecraftVersion") as String
        val props = mapOf(
            "version" to version,
            "apiVersion" to minecraftVersion
        )
        inputs.properties(props)
        filteringCharset = "UTF-8"
        filesMatching("plugin.yml") {
            expand(props)
        }
    }
}
