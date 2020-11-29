param (
    [Parameter(Mandatory = $False)]
    $Suffix,
    [Parameter(Mandatory=$True)]
    [ValidateSet('9.2.0', '9.3.0')]
    $Version,
    [Parameter(Mandatory=$False)]
    $RegistryToRead = "uniformwestus2",

    [switch]
    $SkipLogin,
    [switch]
    $SkipPush,
    [switch]
    $SkipStandalone,
    [switch]
    $SkipSql,
    [switch]
    $SkipSolr
)

$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';

function Invoke-ScriptBlock { 
    $env:REGISTRY = "$($RegistryToRead).azurecr.io/";
    
    $Port = "44100"
    $RegistryUS = "uniformwestus2"
    $REgistryEU = "uniformwesteu"

    if (-not $SkipLogin) {
        az acr login -n $RegistryUS
        az acr login -n $REgistryEU
    }        

    if ($Suffix -and "$Suffix".Length -gt 0) {
        if ($Suffix[0] -ne "-") {
            $Suffix = "-$($Suffix)"
        }
    } else {
        $date = (get-date -Format s).Substring(0, "2020-01-01".Length)
        $Suffix = "-$($date)"
    }

    # input
    $MicrosoftSqlImage = ".azurecr.io/mssql-developer:2017-windowsservercore-ltsc2019"
    $SitecoreStandaloneImage = ".azurecr.io/sitecore-xp-jss-standalone:$Version-windowsservercore-ltsc2019"

    # images to be built
    $HabitatStandaloneImage = ".azurecr.io/habitat-xp-jss-standalone:$Version-windowsservercore-ltsc2019$Suffix"
    $HabitatXpSqlDevImage = ".azurecr.io/habitat-xp-jss-sqldev:$Version-windowsservercore-ltsc2019$Suffix"
    $HabitatXmSqlDevImage = ".azurecr.io/habitat-xm-jss-sqldev:$Version-windowsservercore-ltsc2019$Suffix"
    $SolrImage = ".azurecr.io/habitat-xp-solr:$Version-nanoserver-1809$Suffix"

    # image that is used in the process only
    $HabitatUnicornImage = "habitat-xp-jss-temp:$Version-windowsservercore-ltsc2019"

    # dirs with dockerfiles
    $HabiatatUnicornDir = "$PSScriptRoot\containers\habitat-xp";
    $HabiatatStandaloneDir = "$PSScriptRoot\containers\habitat-xp";

    $source = Join-Path "$HabiatatUnicornDir" -ChildPath "$Version";
    $common = Join-Path "$HabiatatUnicornDir" -ChildPath "common";
    $temp = Join-Path "$HabiatatUnicornDir" -ChildPath "temp";
    $habitat = Join-Path "$HabiatatUnicornDir" -ChildPath "habitat";

    if (-not $SkipStandalone) {
        MKDIR $temp -Force | Out-Null;
        RMDIR $temp -Force -Recurse;
        MKDIR $temp -Force | Out-Null;

        MKDIR $habitat -Force | Out-Null;
        RMDIR $habitat -Force -Recurse;
        MKDIR $habitat -Force | Out-Null;

        # prepare our custom files for docker images
        # including vanila web.config, layers.config and domains.config
        # to be patched by gulp scripts
        XCOPY $source $habitat /S /Y;
        
        XCOPY $common $habitat /S /Y;

        # workaround for stock habitat scripts
        dir "./src/*/*/*/obj" | Remove-Item -Force -Recurse

        # slighly modified habitat scripts that deploy files to the habitat folder (not to run npx gulp deploy twice)
        Write-Host "Deploying habitat to $habitat folder" -ForegroundColor Green
        $env:INSTANCE_ROOT = "$habitat";
        npx gulp deploy;

        # removing all stock Sitecore assemblies
        $stockAssemblies = (Invoke-WebRequest "http://dl.sitecore.net/updater/info/v4/Sitecore%20CMS/$Version/default/index.json" -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty Assemblies | Get-Member | ForEach-Object { return $_.Name }
        $stockAssemblies | ForEach-Object {
            $assemblyPath = "$habitat\bin\$_"
            if (Test-Path $assemblyPath) {
               Remove-Item $assemblyPath -Verbose
            }
        }

        DIR "$habitat\bin\*.pdb" | Remove-Item -Force;
        DIR "$habitat\bin\System.*.dll" | Remove-Item -Force;

        # copying from habitat to temp
        XCOPY $habitat $temp /S /Y;

        # removing unicorn and uniform tools because we don't need it in "production" habitat container (and because it will fail without access to serialization files)
        Get-ChildItem -Path "$temp\bin" -Filter "*Uniform*" | Remove-Item -Force;
        Get-ChildItem -Path "$temp\bin" -Filter "*Unicorn*" | Remove-Item -Force;
        Get-ChildItem -Path "$temp\bin" -Filter "*Rainbow*" | Remove-Item -Force;
        Remove-Item "$temp\Tools" -Force -Recurse; 
        Get-ChildItem -Path "$temp\App_Config" -Filter "*Unicorn*" -Recurse -Directory | Remove-Item -Force -Recurse; 
        Get-ChildItem -Path "$temp\App_Config" -Filter "*Rainbow*" -Recurse -Directory | Remove-Item -Force -Recurse; 
        Get-ChildItem -Path "$temp\App_Config" -Filter "*.config" -Recurse -File | ForEach-Object { 
            $path = $_.FullName; 
            if (([xml](Get-Content $path)).SelectNodes("/configuration/sitecore/unicorn").Count -gt 0) { 
                Write-Host "Removing $path because it contains <unicorn> element"
                Remove-Item $path; 
            }
        }        
        "<configuration><sitecore><sc.variable name=`"rootHostName`" value=`"dev.local`" /></sitecore></configuration>" | Out-File "$temp\App_Config\Environment\Project\Common.Dev.config"

        Write-Host "Building `"production`" habitat package without unicorn and uniform tools (habitat-xp-jss-standalone)" -ForegroundColor Green
        docker build --build-arg "BASE_IMAGE=$RegistryToRead$SitecoreStandaloneImage" -t "$RegistryUS$HabitatStandaloneImage" -t "$REgistryEU$HabitatStandaloneImage" "$HabiatatStandaloneDir"

        if ($LASTEXITCODE -NE 0) {
            exit $LASTEXITCODE;
        }

        Write-Host "Success! Image is built: $RegistryUS/$REgistryEU$HabitatStandaloneImage"

        if (-not $SkipPush) {
            docker push "$RegistryUS$HabitatStandaloneImage"
            docker push "$RegistryEU$HabitatStandaloneImage"
        } else {
            Write-Host "Skipping push"
        }

        if ($SkipSql -and $SkipSolr) {
            exit 0;
        }

        # phase 2
        # re-deploy site to recover unicorn 

        MKDIR $temp -Force | Out-Null;
        RMDIR $temp -Force -Recurse;
        MKDIR $temp -Force | Out-Null;

        XCOPY $habitat $temp /S /Y;

        Write-Host "Building normal habitat package with unicorn and uniform tools (habitat-xp-jss-temp)" -ForegroundColor Green
        docker build --build-arg "BASE_IMAGE=$RegistryToRead$SitecoreStandaloneImage" -t "$HabitatUnicornImage" "$HabiatatUnicornDir"

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
    }

    if ($SkipSql -and $SkipSolr) {
        exit 0;
    }

    try {
        & .\containers\compose\Compose.ps1 -Detach

        if ($LASTEXITCODE -NE 0) {
            exit $LASTEXITCODE;
        }
        
        $env:INSTANCE_ROOT = "$PSScriptRoot\containers\compose\.docker\files";

        Invoke-NonBlockingWebRequest -Url "http://localhost:$Port/Tools/SyncUnicorn.aspx?timeout=720&token=12345"

        Invoke-NonBlockingWebRequest -Url "http://localhost:$Port/Tools/RebuildLinks.aspx?timeout=720&token=12345&databases=master|web"

        Invoke-NonBlockingWebRequest -Url "http://localhost:$Port/Tools/Publish.aspx?timeout=720&token=12345&mode=full&smart=true&source=master&target=web&language=en"

        # we need to find our docker containers that belong to this execution (there could be many similar ones)
        # so get list of all and do only ones that 
        $info = docker ps

        # stop containers to commit images (after saving them to $info)
        & .\containers\compose\Stop.ps1

        if (-not $SkipSql) {
            Copy-Item "$PSScriptRoot\containers\sqldev\Boot.ps1" "$PSScriptRoot\containers\sqldev\files" -Force
            DIR "$PSScriptRoot\containers\sqldev\files\*.ldf" | Remove-Item -Force
            DIR "$PSScriptRoot\containers\sqldev\files\*_Primary.*" | %{ Rename-Item $_.FullName -NewName ($_.Name.Replace('_Primary', ''))}
            
            docker build "$PSScriptRoot\containers\sqldev" --build-arg BASE_IMAGE="$RegistryToRead$MicrosoftSqlImage" -t "$RegistryUS$HabitatXpSqlDevImage" -t "$RegistryEU$HabitatXpSqlDevImage"

            if ($LASTEXITCODE -ne 0) {
                exit $LASTEXITCODE;
            }

            if (-not $SkipPush) {
                docker push $ImageNameUS;
                docker push $ImageNameEU;
            } else {
                Write-Host "Skipping push"
            }

            MKDIR "$PSScriptRoot\containers\sqldev\files-xm" -Force | Out-Null
            RMDIR "$PSScriptRoot\containers\sqldev\files-xm" -Force | Out-Null
            MKDIR "$PSScriptRoot\containers\sqldev\files-xm" -Force | Out-Null
            Copy-Item "$PSScriptRoot\containers\sqldev\files\Sitecore.Core.mdf" "$PSScriptRoot\containers\sqldev\files-xm"
            Copy-Item "$PSScriptRoot\containers\sqldev\files\Sitecore.Master.mdf" "$PSScriptRoot\containers\sqldev\files-xm"
            RMDIR "$PSScriptRoot\containers\sqldev\files" -Recurse -Force
            Rename-Item "$PSScriptRoot\containers\sqldev\files-xm" -NewName "files"

            docker build "$PSScriptRoot\containers\sqldev" --build-arg BASE_IMAGE="$RegistryToRead$MicrosoftSqlImage" -t "$RegistryUS$HabitatXmSqlDevImage" -t "$RegistryEU$HabitatXmSqlDevImage"

            if ($LASTEXITCODE -ne 0) {
                exit $LASTEXITCODE;
            }

            if (-not $SkipPush) {
                docker push $ImageNameUS;
                docker push $ImageNameEU;
            } else {
                Write-Host "Skipping push"
            }
        }

        if (-not $SkipSolr) {
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
        }
    } finally {
        Write-Host "Cleaning up"
        & .\containers\compose\Shutdown.ps1 -Clean
        docker image rm $HabitatUnicornImage
    }
}

function Invoke-NonBlockingWebRequest {
    param(
        [Parameter(Mandatory=$True)]
        [string]$Url,

        [Parameter(Mandatory=$False)]
        $TimeoutSec
    )


    $request = [System.Net.WebRequest]::CreateHttp($url)
    $request.Accept = "text/plain"
    
    if ($timeoutSec) {
        $timeout = [int]::Parse($timeoutSec)
        $request.Timeout = $timeout * 1000
        $request.ReadWriteTimeout = $timeout * 1000
    }

    try
    {
        Write-Host "Sending request to $($request.RequestUri.AbsoluteUri)"
        Write-Host ""
        [System.Net.HttpWebResponse]$resp = $request.GetResponse()    
        Write-Host "Reading the response..."
        Write-Host ""
        Write-Host "StatusCode: $(($resp.StatusDescription)) ($(([int]$resp.StatusCode)))"
        Write-Host ""
        Write-Host "Requesting a response stream..."
        Write-Host ""
                
        $stream = $resp.GetResponseStream()
        try
        {
            Write-Host "Reading the response stream..."
            $SIZE = 128
            $buffer = [char[]]::new($SIZE)
            $encoding = [System.Text.Encoding]::UTF8;
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList (@($stream, $encoding, $false, $SIZE))
            while (-not $reader.EndOfStream)
            {
                $c = $reader.Read($buffer, 0, $SIZE)
                if ($c -gt 0) 
                {
                    Write-Host -NoNewLine -Object ($encoding.GetString($buffer, 0, $c))
                }
            }
        }
        finally {
            if ($stream) {
                $stream.Dispose();
            }
        }

        return 0
    }
    catch
    {
        Write-Host "The remote server returned an error"
        Write-Host ""
        [System.Net.HttpWebResponse]$resp = $_.Response
        Write-Host "StatusCode: $(($resp.StatusDescription)) ($(([int]$resp.StatusCode)))"
        if (-not $resp) {
            throw $_;
        }
        Write-Host ""
        Write-Host "Requesting a response stream..."
        Write-Host ""
        $stream = $resp.GetResponseStream();
        try
        {
            Write-Host "Reading the response stream..."
            $text = new StreamReader(stream).ReadToEnd()
            if ($text.EndsWith("System.Web.HttpApplication.ExecuteStep(IExecutionStep step, Boolean& completedSynchronously)`r`n-->"))
            {
                $text = $text.Substring($text.LastIndexOf("<!--") + "<!-- `r`n".Length)
                $text = $text.Substring(0, $text.Length - "-->".Length)
                $text = "Response was parsed as ASP.NET Exception: `r`n`r`n$text"
            }
            else
            {
                $text = "Response: `r`n$text"
            }

            Write-Host $text
        }
        finally {
            if ($stream) {
                $stream.Dispose();
            }
        }

        return $resp.StatusCode
    }
}

# this must be the last instruction
Invoke-ScriptBlock
