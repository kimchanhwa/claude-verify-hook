# PostToolUse 훅: Claude가 .py 파일을 쓰거나 고치면 문법 검사 → 짝 테스트(pytest)를 자동 실행한다.
# 실패하면 stderr + exit 2로 에러를 Claude에게 돌려보내 스스로 고치게 한다.
# 파이썬·pytest가 없거나 훅 자체에 문제가 생기면 조용히 통과 (Claude 작업을 막지 않게)

$MaxOutputLines = 50   # Claude에게 보낼 에러 출력 최대 줄 수 (넘으면 뒷부분만)
$TestTimeoutSeconds = 30   # 훅 timeout(60초)보다 짧게. 넘으면 테스트를 강제 종료하고 실패로 알린다

# compile()로 문법만 확인한다 (py_compile은 __pycache__를 남김)
$SyntaxCheck = @'
import sys, traceback
path = sys.argv[1]
try:
    compile(open(path, 'rb').read(), path, 'exec')
except (SyntaxError, ValueError) as e:
    sys.stdout.write(''.join(traceback.format_exception_only(type(e), e)))
    sys.exit(1)
'@

function Get-Python([string]$projectDir) {
    foreach ($venv in '.venv', 'venv') {
        $p = Join-Path $projectDir "$venv\Scripts\python.exe"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    # WindowsApps의 python.exe는 스토어 설치 안내용 가짜 실행 파일이라 제외
    Get-Command python -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
        Select-Object -First 1 -ExpandProperty Source
}

# 고친 파일이 테스트면 그 자체, 아니면 test_<이름>.py / <이름>_test.py 를 같은 폴더·tests 폴더에서 찾는다
function Find-TestFile([System.IO.FileInfo]$file, [string]$projectDir) {
    if ($file.Name -match '^test_.*\.py$|_test\.py$') { return $file.FullName }
    $dirs = $file.DirectoryName, (Join-Path $file.DirectoryName 'tests'), (Join-Path $projectDir 'tests')
    foreach ($dir in $dirs) {
        foreach ($name in "test_$($file.BaseName).py", "$($file.BaseName)_test.py") {
            $p = Join-Path $dir $name
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
}

# 훅 timeout으로 끊기면 테스트 중인 python이 고아 프로세스로 남으므로, 직접 시간 제한을 두고 프로세스 트리째 종료한다
function Invoke-Pytest([string]$python, [string]$test, [string]$workDir) {
    $psi = [Diagnostics.ProcessStartInfo]::new($python)
    foreach ($a in '-m', 'pytest', '-q', '-x', '--tb=short', '--disable-warnings', '-p', 'no:cacheprovider', $test) {
        $psi.ArgumentList.Add($a)
    }
    $psi.WorkingDirectory = $workDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TestTimeoutSeconds * 1000)) {
        $p.Kill($true)
        return $null
    }
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Output = @(($stdout.Result + $stderr.Result) -split "`r?`n") }
}

function Exit-WithFeedback([string]$title, [string[]]$output) {
    if ($output.Count -gt $MaxOutputLines) { $output = @('...(앞부분 생략)') + $output[-$MaxOutputLines..-1] }
    [Console]::Error.WriteLine("[자동 검증 실패] $title")
    [Console]::Error.WriteLine(($output -join "`n").TrimEnd())
    [Console]::Error.WriteLine('→ 원인을 확인해 고치세요. 다시 저장하면 자동으로 재검사합니다.')
    exit 2
}

try {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    [Console]::OutputEncoding = [Text.Encoding]::UTF8   # 파이썬의 UTF-8 출력을 깨지지 않게 읽기 위해
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json

    $path = $data.tool_input.file_path
    if ($path -notmatch '\.py$' -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { exit 0 }
    $file = Get-Item -LiteralPath $path
    # Claude Code는 둘 다 넘겨주지만, 없으면 파일이 있는 폴더를 기준으로 한다
    $projectDir = @($env:CLAUDE_PROJECT_DIR, $data.cwd, $file.DirectoryName) | Where-Object { $_ } | Select-Object -First 1
    $python = Get-Python $projectDir
    if (-not $python) { exit 0 }

    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONDONTWRITEBYTECODE = '1'   # 검사 흔적(__pycache__)을 남기지 않게

    $out = @($SyntaxCheck | & $python - $file.FullName 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { Exit-WithFeedback "문법 오류: $($file.FullName)" $out }

    $test = Find-TestFile $file $projectDir
    if (-not $test) { exit 0 }
    & $python -c 'import pytest' 2>$null
    if ($LASTEXITCODE -ne 0) { exit 0 }

    # 프로젝트 루트에서 실행해야 tests/ 안의 테스트가 루트 모듈을 import 할 수 있다
    $inProject = $file.FullName.StartsWith($projectDir, [StringComparison]::OrdinalIgnoreCase)
    $result = Invoke-Pytest $python $test $(if ($inProject) { $projectDir } else { $file.DirectoryName })
    if (-not $result) {
        Exit-WithFeedback "테스트 시간 초과(${TestTimeoutSeconds}초): $test" @('무한 루프나 입력 대기로 멈추는 곳이 없는지 확인하세요.')
    }
    # 1: 테스트 실패, 2: 수집 오류(import 실패 등). 5(테스트 없음)·3·4(pytest 자체 문제)는 통과시킨다
    if ($result.ExitCode -in 1, 2) { Exit-WithFeedback "테스트 실패: $test" $result.Output }
}
catch {
    # 훅 오류가 Claude 작업을 막지 않도록 무시
}
exit 0
