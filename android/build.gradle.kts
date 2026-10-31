allprojects {
    repositories {
        google()
        mavenCentral()
        // Google Home APIs SDK (phone flavour's smart home); a local repo, gitignored. Optional.
        val homeSdk = file("$rootDir/home-sdk")
        if (homeSdk.exists()) maven { url = uri(homeSdk) }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
