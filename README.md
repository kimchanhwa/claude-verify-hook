# claude-verify-hook

[Claude Code](https://claude.com/claude-code)가 `.py` 파일을 쓰거나 고칠 때마다 **문법을 자동으로 검사**하는 훅 플러그인입니다.
문법 오류가 있으면 에러를 Claude에게 돌려보내, Claude가 그 부분만 바로 고치게 합니다.

```
수정 → 문법 검사 → 오류가 있으면 Claude에게 전달 → Claude가 그 부분만 수정 → 다시 검사
```

## 사용 예시

```
👤 calc.py에 평균 구하는 average 함수 만들어줘

🤖 def average(numbers:      ← 괄호를 안 닫음

🪝 [자동 검증 실패] SyntaxError: invalid syntax

🤖 괄호만 닫음 → def average(numbers):

🪝 (통과)
```

## 동작

1. Claude가 `Write`·`Edit` 도구로 `.py` 파일을 저장하면 훅이 실행됩니다.
2. Python `compile()`로 문법만 검사합니다. 코드를 실행하지 않고, `__pycache__`도 남기지 않습니다.
3. 문법 오류가 있으면 exit code 2와 함께 에러를 stderr로 보내고, Claude는 그 오류만 고칩니다.

Claude가 받는 메시지:

```
[자동 검증 실패] 문법 오류: C:\work\calc.py
  File "C:\work\calc.py", line 2
    return sum(numbers) / len(numbers)
    ^
SyntaxError: invalid syntax
→ 이 문법 오류만 고치세요. 다른 부분은 바꾸지 마세요.
```

**테스트는 돌리지 않습니다.** 테스트가 실패하면 코드가 틀렸는지 테스트가 낡았는지 애매해서, Claude에게 자동으로 고치게 하면 원래 설계에서 벗어날 수 있기 때문입니다. 테스트는 필요할 때 직접 요청하세요.

## 요구 사항

- Windows, [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)
- Python: 프로젝트의 파이썬 버전 기준으로 검사하도록 `.venv`·`venv`를 먼저 쓰고, 없으면 PATH의 `python`을 씁니다

## 설치

Claude Code에서 실행합니다. (2.1.275 이상)

```
/plugin install verify-on-edit --marketplace kimchanhwa/claude-verify-hook
```

이전 버전이라면 두 단계로 설치합니다.

```
/plugin marketplace add kimchanhwa/claude-verify-hook
/plugin install verify-on-edit@claude-verify-hook
```

설치 후 Claude Code를 다시 시작하면 적용됩니다. 끄거나 지우려면 `/plugin` 메뉴를 쓰세요.

### 수동 설치 (플러그인 없이)

1. 스크립트를 내려받습니다. (PowerShell)

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude\hooks" | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/kimchanhwa/claude-verify-hook/main/hooks/verify-on-edit.ps1 -OutFile "$HOME\.claude\hooks\verify-on-edit.ps1" -UseBasicParsing
```

2. `~/.claude/settings.json`에 등록합니다. 이미 `PostToolUse`가 있으면 배열에 항목만 추가하세요.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hooks/verify-on-edit.ps1",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

특정 프로젝트에만 쓰려면 스크립트를 `<프로젝트>/.claude/hooks/`에 두고 `<프로젝트>/.claude/settings.json`에 등록합니다. 이때 명령의 경로는 `"$CLAUDE_PROJECT_DIR/.claude/hooks/verify-on-edit.ps1"`로 씁니다.

플러그인과 수동 설치를 함께 쓰면 검사가 두 번 실행되니 하나만 쓰세요.

## 검사 없이 통과하는 경우

Claude 작업을 막지 않도록, 아래 경우에는 조용히 통과합니다.

- `.py` 파일이 아님
- Python이 없음 (Microsoft Store 설치 안내용 가짜 `python.exe`도 제외)
- 훅 스크립트 자체에서 오류가 남

## 주의

- 문법만 봅니다. 문법은 맞지만 동작이 틀린 버그(로직 오류, 없는 이름 참조 등)는 잡지 않습니다.
- `Write`·`Edit` 도구만 감지합니다. Claude가 셸 명령으로 고친 파일은 검사하지 않습니다.
- 저장할 때마다 약 0.7초가 걸립니다.
