/**
 * FE Health Test — 5단계 FE 도메인 전환 검증
 *
 * 용도: re-fit.kr DNS를 CloudFront로 변경한 직후, 페이지 응답 정상 여부 확인
 * 실행: k6 run --dns-ttl=0s scripts/fe-health-test.js
 *
 * 타겟: https://re-fit.kr (FE 페이지)
 * 검증: HTTP 200, HTML 응답 포함, p95 < 2000ms
 */
import { FE_THRESHOLDS } from "../utils/config.js";
import { fePagesScenario } from "../scenarios/fe-pages.js";

export const options = {
  vus: 5,
  duration: "30m",
  thresholds: FE_THRESHOLDS,
};

export default function () {
  fePagesScenario();
}
