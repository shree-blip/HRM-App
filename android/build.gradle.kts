allprojects {
    repositories {
        google()
        mavenCentral()
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

    // Force every Android module (app + plugins like file_picker) to compile
    // against API 36+, which flutter_plugin_android_lifecycle now requires.
    // Compile-time only — does not change each module's targetSdk/minSdk.
    // Registered here (before evaluationDependsOn below) so the project is not
    // yet evaluated when the callback is attached.
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val current = android.javaClass.getMethod("getCompileSdkVersion").invoke(android) as? String
                val level = current?.removePrefix("android-")?.toIntOrNull() ?: 0
                if (level < 36) {
                    android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
                }
            } catch (_: Exception) {
                // Non-Android subproject or incompatible extension — ignore.
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
