// Root build file for all Android subprojects and modules.
// Project-wide plugins and repositories are configured here.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Write build output outside the android/ directory so it matches
// Flutter's expected root-level build structure.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
