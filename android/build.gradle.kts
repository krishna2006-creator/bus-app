plugins {
    id("com.google.gms.google-services") version "4.4.4" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // legacy google-services classpath removed — using plugins DSL instead
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
// Ensure the Firebase BoM is available to all subprojects (some FlutterFire plugins
// declare Firebase dependencies without versions and expect the app to provide the BoM).
subprojects {
    afterEvaluate {
        try {
            dependencies {
                add("implementation", enforcedPlatform("com.google.firebase:firebase-bom:34.6.0"))
            }
        } catch (e: Exception) {
            // ignore if a subproject doesn't have a dependencies container at this time
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
