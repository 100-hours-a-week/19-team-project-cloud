from __future__ import annotations

import json
import os
from typing import Any, Dict

import urllib3

# PoolManager는 Lambda 컨테이너가 재사용될 때까지 살아 있으므로,
# 모듈 레벨에 한 번만 생성해 두어 커넥션 재사용 이점을 얻는다.
http = urllib3.PoolManager()


def _get_alarm_payload(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    SNS -> Lambda 로 들어온 이벤트에서 CloudWatch Alarm payload를 안전하게 추출한다.

    CloudWatch Alarm SNS 메시지 포맷에 대한 최소한의 방어적 파싱만 수행하고,
    필수 필드가 없을 경우에도 기본값을 채운다.
    """
    record = event.get("Records", [{}])[0]
    sns = record.get("Sns", {})

    # CloudWatch Alarm 메시지는 JSON 문자열로 전달된다.
    raw_message = sns.get("Message", "{}")
    try:
        message = json.loads(raw_message)
    except json.JSONDecodeError:
        # 형식이 깨져도 전체 Lambda가 죽지 않도록 하고, 최소 정보만 사용한다.
        message = {}

    alarm_name = sns.get("Subject") or message.get("AlarmName") or "Infrastructure Alert"
    alarm_state = message.get("NewStateValue", "ALARM")
    alarm_reason = message.get("NewStateReason", "No reason provided")
    alarm_description = message.get("AlarmDescription")  # CloudWatch에 설정해 둔 한글 설명(없을 수 있음)
    alarm_time = sns.get("Timestamp", "")

    # Discord description: CloudWatch NewStateReason + AlarmDescription(알람 설명).
    # AlarmDescription 은 CloudWatch 콘솔/CLI 에서 설정한 값이 SNS 메시지에 포함되어 전달된다.
    if alarm_description:
        description = f"{alarm_reason}\n\n{alarm_description}"
    else:
        description = alarm_reason

    return {
        "name": alarm_name,
        "state": alarm_state,
        "reason": alarm_reason,
        "description": description,
        "time": alarm_time,
    }


def _build_discord_embed(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    CloudWatch Alarm 정보를 Discord Embed 포맷으로 변환한다.
    """
    state = payload["state"]
    state_label = "ALARM" if state == "ALARM" else "OK"

    # Discord embed color (decimal RGB)
    color_alarm = 0xE74C3C  # Red-ish
    color_ok = 0x2ECC71     # Green-ish
    color = color_alarm if state == "ALARM" else color_ok

    return {
        "title": f"[{state_label}] {payload['name']}",
        "description": payload["description"],
        "color": color,
        "fields": [
            {"name": "State", "value": state, "inline": True},
            {"name": "Timestamp", "value": payload["time"], "inline": True},
        ],
        "footer": {"text": "Re-Fit Infrastructure Monitoring"},
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    CloudWatch Alarm -> SNS -> Lambda 이벤트를 받아 Discord Webhook으로 전송한다.

    - 입력:
      - event: SNS가 전달한 Lambda 이벤트(JSON)
      - context: Lambda 실행 컨텍스트 (현재 구현에서는 사용하지 않음)
    - 필수 환경 변수:
      - DISCORD_WEBHOOK: Discord Webhook URL
    """
    webhook_url = os.environ["DISCORD_WEBHOOK"]

    alarm_payload = _get_alarm_payload(event)
    embed = _build_discord_embed(alarm_payload)
    payload = {"embeds": [embed]}

    try:
        response = http.request(
            "POST",
            webhook_url,
            body=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        return {
            "statusCode": response.status,
            "body": json.dumps("Message sent to Discord"),
        }
    except Exception as exc:  # Lambda 로그에서 원인 추적이 쉬우도록 예외 그대로 기록
        print(f"Error sending to Discord: {exc}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error sending to Discord: {exc}"),
        }