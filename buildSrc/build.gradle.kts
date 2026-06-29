plugins {
    `kotlin-dsl`
}

repositories {
    gradlePluginPortal()
    mavenCentral()
}

dependencies {
    implementation("com.gradleup.shadow:shadow-gradle-plugin:9.4.3")
    implementation("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.21")
    implementation("org.jetbrains.kotlin:kotlin-serialization:2.3.21")
}
