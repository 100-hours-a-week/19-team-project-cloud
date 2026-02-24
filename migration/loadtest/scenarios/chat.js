import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { BASE_URL, WS_BASE_URL } from '../utils/config.js';
import {
  getTokenForVU,
  authHeaders,
  checkJsonResponse,
  checkResponse,
  stompConnect,
  stompSubscribe,
  stompSend,
  stompDisconnect,
  errorCounter,
} from '../utils/helpers.js';

/**
 * 채팅 REST API 시나리오
 * 1. 채팅방 목록 조회
 * 2. 채팅방 메시지 조회
 */
export function chatRestScenario() {
  const token = getTokenForVU();
  const params = authHeaders(token.access_token);

  // 1. 채팅방 목록 조회
  const listRes = http.get(`${BASE_URL}/api/v1/chats`, params);
  const listData = checkJsonResponse(listRes, 'GET /chats');
  sleep(1);

  // 2. 첫 번째 채팅방의 메시지 조회
  const chatRooms = listData?.content || listData?.data || [];
  if (chatRooms.length > 0) {
    const chatId = chatRooms[0].chat_id || chatRooms[0].id;
    const msgRes = http.get(
      `${BASE_URL}/api/v1/chats/${chatId}/messages?size=20`,
      params,
    );
    checkResponse(msgRes, 'GET /chats/{id}/messages');
    sleep(1);
  }
}

/**
 * 채팅 WebSocket STOMP 시나리오
 * 연결 → 구독 → 메시지 전송 → 수신 확인 → 연결 종료
 */
export function chatWebSocketScenario() {
  const token = getTokenForVU();
  const params = authHeaders(token.access_token);

  // 먼저 REST로 채팅방 목록 조회해서 채팅방 ID 획득
  const listRes = http.get(`${BASE_URL}/api/v1/chats`, params);
  const listData = checkJsonResponse(listRes, 'GET /chats (for WS)');
  const chatRooms = listData?.content || listData?.data || [];
  if (chatRooms.length === 0) return;

  const chatId = chatRooms[0].chat_id || chatRooms[0].id;

  // WebSocket STOMP 연결
  const wsUrl = `${WS_BASE_URL}?token=${token.access_token}`;
  const res = ws.connect(wsUrl, {}, function (socket) {
    let messageReceived = false;

    socket.on('open', () => {
      // STOMP CONNECT
      socket.send(stompConnect(token.access_token));
    });

    socket.on('message', (data) => {
      // STOMP CONNECTED 응답 확인
      if (data.startsWith('CONNECTED')) {
        // 채팅방 구독
        socket.send(stompSubscribe(`/queue/chat.${chatId}`));

        // 메시지 전송
        sleep(1);
        socket.send(
          stompSend('/app/chat.sendMessage', {
            chat_id: chatId,
            content: `k6 부하테스트 메시지 ${Date.now()}`,
            message_type: 'TEXT',
            client_message_id: `k6-${__VU}-${__ITER}-${Date.now()}`,
          }),
        );
      }

      // MESSAGE 프레임 수신 확인
      if (data.startsWith('MESSAGE')) {
        messageReceived = true;
      }
    });

    socket.on('error', (e) => {
      errorCounter.add(1, { endpoint: 'websocket', error: e.message || 'ws_error' });
    });

    // 메시지 수신 대기 후 종료 (최대 10초)
    socket.setTimeout(() => {
      check(null, {
        'WebSocket message received': () => messageReceived,
      });
      socket.send(stompDisconnect());
      socket.close();
    }, 10000);
  });

  check(res, {
    'WebSocket connection status 101': (r) => r && r.status === 101,
  });
  sleep(1);
}

/**
 * 채팅방 목록만 (경량)
 */
export function chatListOnly() {
  const token = getTokenForVU();
  const res = http.get(`${BASE_URL}/api/v1/chats`, authHeaders(token.access_token));
  checkResponse(res, 'GET /chats');
  sleep(1);
}
