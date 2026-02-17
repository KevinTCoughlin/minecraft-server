plugins {
    kotlin("jvm")
    id("com.gradleup.shadow")
}

kotlin {
    jvmToolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
        vendor.set(JvmVendorSpec.ADOPTIUM)
    }
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
