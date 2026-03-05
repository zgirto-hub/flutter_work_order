$BUILD_DATE = Get-Date -Format "yyyy-MM-dd_HH-mm"

Write-Host "Building Flutter Web..."
Write-Host "Build date: $BUILD_DATE"

flutter build web --dart-define=BUILD_DATE=$BUILD_DATE

Write-Host "Build complete."