param (
    [switch]
    $SkipPush,
    [switch]
    $SkipStandalone,
    [switch]
    $SkipSql,
    [switch]
    $SkipSolr
)

function Invoke-ScriptBlock {
    $Version = "9.2.0"
    $RegistryName = "altola"
    $Port = "44100"

    # input
    $SitecoreStandaloneImage = "$RegistryName.azurecr.io/sitecore-xp-jss-standalone:$Version-windowsservercore-ltsc2019"

    # images to be built
    $HabitatStandaloneImage = "$RegistryName.azurecr.io/habitat-xp-jss-standalone:$Version-windowsservercore-ltsc2019"
    $SqlImage = "$RegistryName.azurecr.io/habitat-xp-jss-sqldev:$Version-windowsservercore-ltsc2019"
    $SolrImage = "$RegistryName.azurecr.io/habitat-xp-solr:$Version-nanoserver-1809"

    # image that is used in the process only
    $HabitatUnicornImage = "$RegistryName.azurecr.io/habitat-xp-jss-unicorn:$Version-windowsservercore-ltsc2019"

    # dirs with dockerfiles
    $HabiatatUnicornDir = "$PSScriptRoot\containers\habitat-xp";
    $HabiatatStandaloneDir = "$PSScriptRoot\containers\habitat-xp";

    $source = Join-Path "$HabiatatUnicornDir" -ChildPath "$Version";
    $common = Join-Path "$HabiatatUnicornDir" -ChildPath "common";
    $tools = Join-Path "$HabiatatUnicornDir" -ChildPath "tools";
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

        # workaround for stock habitat scripts
        dir src -Filter obj -Recurse | rmdir -Force -Recurse

        # slighly modified habitat scripts that deploy files to the habitat folder (not to run npx gulp deploy twice)
        Write-Host "Deploying habitat to $habitat folder" -ForegroundColor Green
        $env:INSTANCE_ROOT = "$habitat";
        npx gulp deploy;

        # copying from habitat to temp
        XCOPY $habitat $temp /S /Y;

        # copying common files to temp
        XCOPY $common $temp /S /Y;

        # removing unicorn because we don't need it in "production" habitat container (and because it will fail without access to serialization files)
        Get-ChildItem -Path "$temp\bin" -Filter "*Unicorn*" | Remove-Item -Force;
        Get-ChildItem -Path "$temp\bin" -Filter "*Rainbow*" | Remove-Item -Force;
        Get-ChildItem -Path "$temp\App_Config" -Filter "*Unicorn*" -Recurse -Directory | Remove-Item -Force -Recurse; 
        Get-ChildItem -Path "$temp\App_Config" -Filter "*Rainbow*" -Recurse -Directory | Remove-Item -Force -Recurse; 
        Get-ChildItem -Path "$temp\App_Config" -Filter "*.config" -Recurse -File | ForEach-Object { 
            $path = $_.FullName; 
            if (([xml](Get-Content $path)).SelectNodes("/configuration/sitecore/unicorn").Count -gt 0) { 
                Remove-Item $path; 
            }
        }
        "<configuration><sitecore><sc.variable name=`"rootHostName`" value=`"dev.local`" /></sitecore></configuration>" | Out-File "$temp\App_Config\Environment\Project\Common.Dev.config"

        Write-Host "Building `"production`" habitat package without unicorn (habitat-xp-jss-standalone)" -ForegroundColor Green
        docker build --build-arg "BASE_IMAGE=$SitecoreStandaloneImage" -t "$HabitatStandaloneImage" "$HabiatatStandaloneDir"

        if ($LASTEXITCODE -NE 0) {
            exit $LASTEXITCODE;
        }

        Write-Host "Success! Image is built: $HabitatStandaloneImage"

        if (-not $SkipPush) {
            docker push "$HabitatStandaloneImage"
        } else {
            Write-Host "Skipping push"
        }

        # phase 2
        # re-deploy site to recover unicorn 

        MKDIR $temp -Force | Out-Null;
        RMDIR $temp -Force -Recurse;
        MKDIR $temp -Force | Out-Null;

        XCOPY $habitat $temp /S /Y;

        # add tools to sync unicorn and publish
        XCOPY $tools $temp /S /Y;

        Write-Host "Building normal habitat package with unicorn (habitat-xp-jss-unicorn)" -ForegroundColor Green
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

        & .\containers\compose\Shutdown.ps1 -Clean
            
        if ($LASTEXITCODE -NE 0) {
            exit $LASTEXITCODE;
        }
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

        Invoke-NonBlockingWebRequest -Url "http://localhost:$Port/Tools/Publish.aspx?timeout=720&token=12345&mode=full&smart=true&source=master&target=web&language=en"

        # we need to find our docker containers that belong to this execution (there could be many similar ones)
        # so get list of all and do only ones that 
        $info = docker ps

        # stop containers to commit images (after saving them to $info)
        & .\containers\compose\Stop.ps1

        if (-not $SkipSql) {
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
