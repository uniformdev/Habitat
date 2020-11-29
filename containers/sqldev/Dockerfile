# escape=`
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ENV ACCEPT_EULA='Y' `
    sa_password='HASH-epsom-sunset-cost7!' `
    INSTALL_PATH='C:\\install\\' `
    DATA_PATH='C:\\data\\'

COPY files ${INSTALL_PATH}
    
RUN New-Item -Path $env:DATA_PATH -ItemType Directory | Out-Null; `
    Copy-Item -Path (Join-Path $env:INSTALL_PATH "\\Boot.ps1") -Destination 'C:\\'; `
    Get-ChildItem -Path $env:INSTALL_PATH -Exclude "*.mdf", "*.ldf" | Remove-Item -Force; 

CMD C:/Boot.ps1 -InstallPath $env:INSTALL_PATH -DataPath $env:DATA_PATH
