plugins {
    id("paper-plugin")
}

dependencies {
    compileOnly(libs.paper.api)
    implementation(libs.kotlin.stdlib)

    testImplementation(libs.paper.api)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
}
