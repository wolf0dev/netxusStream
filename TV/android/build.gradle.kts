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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// better_player_enhanced 1.0.4 declara compileSdk 34 mientras Media3 1.5 y
// wakelock_plus piden 36. El propio módulo no se puede reconfigurar desde aquí
// (AGP ya ha leído compileSdk cuando llega el root), así que saltamos solo la
// comprobación de metadatos AAR de ese plugin. El APK se compila con el
// compileSdk 36 de la app y Media3 funciona desde API 21.
subprojects {
    if (name == "better_player_enhanced") {
        tasks.matching { it.name.contains("AarMetadata") }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
