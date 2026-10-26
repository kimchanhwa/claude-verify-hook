# claude-verify-hook

[Claude Code](https://claude.com/claude-code)가 `.py` 파일을 쓰거나 고칠 때마다 **문법 검사와 짝 테스트(pytest)를 자동으로 실행**하는 PostToolUse 훅입니다.
검사에 실패하면 에러를 Claude에게 돌려보내, 사람이 개입하지 않아도 Claude가 바로 고치게 합니다.

```
수정 → 자동 검증 → 실패하면 에러 전달 → Claude가 재수정 → 다시 검증
```

## 동작

1. Claude가 `Write`·`Edit` 도구로 `.py` 파일을 저장하면 훅이 실행됩니다.
2. `compile()`로 문법을 검사합니다. (`__pycache__`를 남기지 않음)
3. 짝 테스트 파일을 찾습니다. 고친 파일이 테스트 파일이면 그 파일 자체를 씁니다.
   - 파일 이름: `test_<이름>.py`, `<이름>_test.py`
   - 찾는 순서: 같은 폴더 → 같은 폴더의 `tests/` → 프로젝트 루트의 `tests/`
4. 짝 테스트가 있으면 pytest로 실행합니다. (30초 제한, `.pytest_cache`를 남기지 않음)
5. 실패하면 exit code 2와 함께 에러를 stderr로 보내고, Claude가 이를 보고 고칩니다.

Claude가 받는 메시지 예시:

```
[자동 검증 실패] 테스트 실패: C:\work\test_calc.py
E   assert 5.0 == 4
E    +  where 5.0 = average([2, 4, 6])
FAILED test_calc.py::test_average - assert 5.0 == 4
→ 원인을 확인해 고치세요. 다시 저장하면 자동으로 재검사합니다.
```

## 요구 사항

- Windows, [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`)
- Python: 프로젝트의 `.venv`·`venv`를 먼저 쓰고, 없으면 PATH의 `python`을 씁니다
- pytest: 없으면 문법 검사만 합니다

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
- pytest가 없거나, 짝 테스트에 테스트 함수가 없음
- pytest 설정 오류처럼 pytest 자체가 실행되지 못함
- 훅 스크립트 자체에서 오류가 남

## 설정

스크립트 위쪽 변수로 조절합니다. 플러그인으로 설치한 스크립트는 업데이트할 때 덮어써지므로, 값을 바꿔 쓰려면 수동 설치를 쓰세요.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `$MaxOutputLines` | 50 | Claude에게 보낼 에러 출력 최대 줄 수 (넘으면 뒷부분만) |
| `$TestTimeoutSeconds` | 30 | 테스트 시간 제한. 넘으면 테스트 프로세스를 종료하고 실패로 알립니다. settings.json의 `timeout`보다 짧아야 합니다 |

## 주의

- **짝 테스트가 있으면 저장할 때마다 테스트 코드가 실행됩니다.** 신뢰할 수 없는 저장소에서는 훅을 끄세요.
- `Write`·`Edit` 도구만 감지합니다. Claude가 셸 명령으로 고친 파일은 검사하지 않습니다.
- 함수 이름을 바꾸고 테스트는 나중에 고치는 식으로 작업하면, 중간 단계에서도 실패 알림이 갈 수 있습니다.
- 저장할 때마다 약 0.7초, 짝 테스트가 있으면 약 1.5초가 더 걸립니다.
