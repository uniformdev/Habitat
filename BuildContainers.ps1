param (
    [switch]
    $SkipPush
)

$Version = "9.2.0"
$RegistryName = "altola"

# input
$SitecoreStandaloneImage = "$RegistryName.azurecr.io/sitecore-xp-jss-standalone:$Version-windowsservercore-ltsc2019"

# images to be built
$HabitatStandaloneImage = "$RegistryName.azurecr.io/habitat-xp-jss-standalone:$Version-windowsservercore-ltsc2019"
$SqlImage = "$RegistryName.azurecr.io/habitat-xp-jss-sqldev:$Version-windowsservercore-ltsc2019"
$SolrImage = "$RegistryName.azurecr.io/habitat-xp-solr:$Version-windowsservercore-ltsc2019"

# image that is used in the process only
$HabitatUnicornImage = "$RegistryName.azurecr.io/habitat-xp-jss-unicorn:$Version-windowsservercore-ltsc2019"

# dirs with dockerfiles
$HabiatatUnicornDir = "$PSScriptRoot\containers\habitat-xp-jss-unicorn";
$HabiatatStandaloneDir = "$PSScriptRoot\containers\habitat-xp-jss-standalone";

$source = Join-Path "$HabiatatUnicornDir" -ChildPath "$Version";
$temp = Join-Path "$HabiatatUnicornDir" -ChildPath "temp";

MKDIR $temp -Force | Out-Null;
RMDIR $temp -Force -Recurse;
MKDIR $temp -Force | Out-Null;

# prepare our custom files for docker images
# including vanila web.config, layers.config and domains.config
# to be patched by gulp scripts
XCOPY $source $temp /S /Y;

# workaround for stock habitat scripts
dir src -Filter obj -Recurse | rmdir -Force -Recurse

# slighly modified habitat scripts that deploy files to the temp folder
Write-Host "Deploying habitat to $temp folder" -ForegroundColor Green
$env:INSTANCE_ROOT = "$temp";
npx gulp deploy;

if ($LASTEXITCODE -NE 0) {
    exit $LASTEXITCODE;
}

Write-Host "Building habitat package (habitat-xp-jss-unicorn)" -ForegroundColor Green
docker build --build-arg "BASE_IMAGE=$SitecoreStandaloneImage" -t "$HabitatUnicornImage" "$HabiatatUnicornDir"

if ($LASTEXITCODE -NE 0) {
    exit $LASTEXITCODE;
}

Write-Host "Success! Image is built: $HabitatUnicornImage"

# no need to push this image because it contains unicorn that will be removed, saved with different name and pushed
# if (-not $SkipPush) {
#     docker push "$HabitatUnicornImage"
# } else {
#     Write-Host "Skipping push"
# }

Write-Host "Building habitat-without-unicorn package (habitat-xp-jss-standalone)" -ForegroundColor Green
docker build --build-arg "BASE_IMAGE=$HabitatUnicornImage" -t "$HabitatStandaloneImage" "$HabiatatStandaloneDir"

if ($LASTEXITCODE -NE 0) {
    exit $LASTEXITCODE;
}

Write-Host "Success! Image is built: $HabitatStandaloneImage"

if (-not $SkipPush) {
    docker push "$HabitatStandaloneImage"
} else {
    Write-Host "Skipping push"
}

& .\containers\compose\Shutdown.ps1 -Clean
    
if ($LASTEXITCODE -NE 0) {
    exit $LASTEXITCODE;
}

try {
    & .\containers\compose\Compose.ps1 -Detach

    if ($LASTEXITCODE -NE 0) {
        exit $LASTEXITCODE;
    }
    
    $env:INSTANCE_ROOT = "$PSScriptRoot\containers\compose\.docker\files";

    # these files are already inside the container so it looks silly
    # but further gulp will need to modify them
    xcopy $temp $env:INSTANCE_ROOT /S /Y;

    MKDIR "$env:INSTANCE_ROOT\App_config\Include" -Force | Out-Null
    npx gulp Sync-Unicorn

    if ($LASTEXITCODE -NE 0) {
        exit $LASTEXITCODE;
    }
    
    # we need to find our docker containers that belong to this execution (there could be many similar ones)
    # so get list of all and do only ones that 
    $info = docker ps

    # stop containers to commit images (after saving them to $info)
    & .\containers\compose\Stop.ps1

    $done = $false;
    $info | where { $_ -like "*:44151*" } | foreach {
        # 2cf343219ca6        altola.azurecr.io/sitecore-xp-jss-sqldev:9.2.0-windowsservercore-ltsc2019      "powershell -Command…"   23 minutes ago      Up 23 minutes (healthy)   0.0.0.0:44151->1433/tcp   compose_sql_1
        $sha = $_.Substring(0, "2cf343219ca6".Length);
        if ($done) {
            return;
        }

        Write-Host "Committing $sha as $SqlImage"
        docker commit $sha "$SqlImage"
        if (-not $SkipPush) {
            Write-Host "Pushing $SqlImage"
            docker push "$SqlImage"
        }

        $done = $true;
    }

    if (-not $done) {
        Write-Error "Failed to find sqldev container among these:"
        $info

        exit -1;
    }

    $done = $false;
    $info | where { $_ -like "*:44111*" } | foreach {
        # 970226c096a6        altola.azurecr.io/sitecore-xp-solr:9.2.0-nanoserver-1809                       "cmd /S /C Boot.cmd …"   23 minutes ago      Up 23 minutes             0.0.0.0:44111->8983/tcp   compose_solr_1
        $sha = $_.Substring(0, "970226c096a6".Length);
        if ($done) {
            return;
        }

        Write-Host "Committing $sha as $SolrImage"
        docker commit $sha "$SolrImage"
        if (-not $SkipPush) {
            Write-Host "Pushing $SolrImage"
            docker push "$SolrImage"
        }

        $done = $true;
    }

    if (-not $done) {
        Write-Error "Failed to find solr container among these:"
        $info

        exit -1;
    }
} finally {
    & .\containers\compose\Shutdown.ps1
}