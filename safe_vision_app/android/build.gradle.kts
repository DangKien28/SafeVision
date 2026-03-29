allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// --- CÁCH FIX MỚI: ÉP NAMESPACE TRỰC TIẾP ---
subprojects {
    // Thay vì afterEvaluate, ta dùng pluginManager để bắt đúng lúc Android Plugin được nạp
    pluginManager.withPlugin("com.android.library") {
        val android = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android.namespace == null && project.name.contains("tflite_flutter")) {
            android.namespace = "com.tfliteflutter.tflite_flutter"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}