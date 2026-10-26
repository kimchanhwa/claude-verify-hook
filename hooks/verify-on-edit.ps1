# PostToolUse 훅: Claude가 .py 파일을 쓰거나 고치면 문법을 검사한다.
# 문법 오류가 있으면 stderr + exit 2로 에러를 Claude에게 돌려보내 그 부분만 고치게 한다.
# 테스트는 돌리지 않는다: 테스트 실패는 코드와 테스트 중 무엇이 틀렸는지 애매해서, 자동으로 고치게 하면 원래 설계에서 벗어날 수 있다
# 파이썬이 없거나 훅 자체에 문제가 생기면 조용히 통과 (Claude 작업을 막지 않게)

# compile()로 문법만 확인한다. 코드를 실행하지 않고, py_compile과 달리 __pycache__도 남기지 않는다
$SyntaxCheck = @'
import sys, traceback
path = sys.argv[1]
try:
    compile(open(path, 'rb').read(), path, 'exec')
except (SyntaxError, ValueError) as e:
    sys.stdout.write(''.join(traceback.format_exception_only(type(e), e)))
    sys.exit(1)
'@

# 프로젝트의 파이썬 버전 기준으로 검사해야 하므로 venv를 먼저 쓴다
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
    $out = @($SyntaxCheck | & $python - $file.FullName 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("[자동 검증 실패] 문법 오류: $($file.FullName)")
        [Console]::Error.WriteLine(($out -join "`n").TrimEnd())
        [Console]::Error.WriteLine('→ 이 문법 오류만 고치세요. 다른 부분은 바꾸지 마세요.')
        exit 2
    }
}
catch {
    # 훅 오류가 Claude 작업을 막지 않도록 무시
}
exit 0
