import http from 'k6/http';
import { sleep, check } from 'k6';

export let options = {
  stages: [
    { duration: '10s', target: 5 },
    { duration: '30s', target: 30 },
    { duration: '20s', target: 60 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.05'],
  },
};

const BASE = __ENV.K6_HOST || 'http://localhost:8080';

export default function () {
  // Test portal login endpoint
  const loginRes = http.post(`${BASE}/login`, {
    username: 'testuser',
    password: 'testpass',
  });
  check(loginRes, {
    'login returns 200 or 401': (r) => r.status === 200 || r.status === 401,
  });

  sleep(1);

  // Test employee list endpoint
  const listRes = http.get(`${BASE}/api/employees`);
  check(listRes, {
    'list endpoint returns 200': (r) => r.status === 200,
  });

  sleep(1);
}
