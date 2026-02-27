param(
  [string]$Mode = "quick"
)

$ErrorActionPreference = "Stop"

try {
  [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
  # Não bloquear o gate por limitação de host/terminal
}

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ApiBaseUrl = if ($env:API_BASE_URL) { $env:API_BASE_URL.TrimEnd('/') } else { "http://localhost:8080" }

function Write-Header([string]$Title) {
  Write-Host ""
  Write-Host "============================================================"
  Write-Host $Title
  Write-Host "============================================================"
}

function Ensure-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Comando não encontrado: $Name"
  }
}

function Invoke-ProbeRequest {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$Method,
    [string]$Body
  )

  try {
    if ($Method -eq "POST") {
      $response = Invoke-WebRequest -Uri $Url -Method Post -UseBasicParsing -TimeoutSec 5 -ContentType "application/json" -Body $Body
    } else {
      $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 5
    }

    return @{
      StatusCode = [int]$response.StatusCode
      ContentType = [string]$response.Headers["Content-Type"]
      Body = [string]$response.Content
    }
  }
  catch {
    $resp = $_.Exception.Response
    if (-not $resp) {
      return $null
    }

    $body = ""
    try {
      $stream = $resp.GetResponseStream()
      if ($stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
        $reader.Close()
      }
    }
    catch {
      $body = ""
    }

    return @{
      StatusCode = [int]$resp.StatusCode
      ContentType = [string]$resp.Headers["Content-Type"]
      Body = [string]$body
    }
  }
}

function Test-ApiProbeResponse([hashtable]$Probe) {
  if (-not $Probe) { return $false }

  $statusOk = @(200, 400, 401, 403, 405, 503) -contains $Probe.StatusCode
  if (-not $statusOk) { return $false }

  $contentTypeRaw = if ($null -ne $Probe.ContentType) { [string]$Probe.ContentType } else { "" }
  $contentType = $contentTypeRaw.ToLowerInvariant()
  if (-not $contentType.StartsWith("application/json")) { return $false }

  $body = if ($null -ne $Probe.Body) { [string]$Probe.Body } else { "" }
  if ($body -notmatch "status|error|token|user|message") { return $false }

  return $true
}

function Test-BackendApiReady {
  $healthProbe = Invoke-ProbeRequest -Url "$ApiBaseUrl/health/ready" -Method "GET"
  if (Test-ApiProbeResponse -Probe $healthProbe) {
    return $true
  }

  $authProbe = Invoke-ProbeRequest -Url "$ApiBaseUrl/auth/login" -Method "POST" -Body "{}"
  return (Test-ApiProbeResponse -Probe $authProbe)
}

function Run-BackendQuick {
  Write-Header "Backend quick checks"
  Push-Location (Join-Path $RootDir "server")
  try {
    dart test
  }
  finally {
    Pop-Location
  }
}

function Run-BackendFull {
  Write-Header "Backend full checks"
  Push-Location (Join-Path $RootDir "server")
  try {
    if (Test-BackendApiReady) {
      Write-Host "ℹ️ API detectada em $ApiBaseUrl — habilitando testes de integração backend."
      $env:RUN_INTEGRATION_TESTS = "1"
      $env:TEST_API_BASE_URL = $ApiBaseUrl
      dart test -j 1
    }
    else {
      Write-Host "⚠️ API não detectada (ou resposta JSON esperada ausente) em $ApiBaseUrl."
      Write-Host "   Rodando suíte backend sem integração."
      Write-Host "   Dica: inicie 'cd server; dart_frog dev' ou defina API_BASE_URL para sua URL de API."
      dart test
    }
  }
  finally {
    Pop-Location
  }
}

function Run-FrontendQuick {
  Write-Header "Frontend quick checks"
  Push-Location (Join-Path $RootDir "app")
  try {
    flutter analyze --no-fatal-infos
  }
  finally {
    Pop-Location
  }
}

function Run-FrontendFull {
  Write-Header "Frontend full checks"
  Push-Location (Join-Path $RootDir "app")
  try {
    flutter analyze --no-fatal-infos
    flutter test
  }
  finally {
    Pop-Location
  }
}

function Show-Usage {
  @"
Uso:
  .\scripts\quality_gate.ps1 quick   # validação rápida (dart test + flutter analyze)
  .\scripts\quality_gate.ps1 full    # validação completa (dart test + flutter analyze + flutter test)

Dica:
  Use 'quick' durante implementação e 'full' antes de concluir item/sprint.
  No modo 'full', se a API responder corretamente em API_BASE_URL
  (default: http://localhost:8080), os testes de integração backend
  são habilitados automaticamente.

Exemplos:
  .\scripts\quality_gate.ps1 full
  `$env:API_BASE_URL='https://sua-api.host'; .\scripts\quality_gate.ps1 full
"@
}

try {
  Ensure-Command "dart"
  Ensure-Command "flutter"

  switch ($Mode.ToLowerInvariant()) {
    "quick" {
      Run-BackendQuick
      Run-FrontendQuick
      break
    }
    "full" {
      Run-BackendFull
      Run-FrontendFull
      break
    }
    "help" {
      Show-Usage
      exit 0
    }
    "-h" {
      Show-Usage
      exit 0
    }
    "--help" {
      Show-Usage
      exit 0
    }
    default {
      throw "Modo inválido: $Mode`n`n$(Show-Usage)"
    }
  }

  Write-Header "Quality gate concluído"
  Write-Host "✅ Todos os checks do modo '$Mode' passaram."
}
catch {
  Write-Host "❌ $($_.Exception.Message)"
  exit 1
}
