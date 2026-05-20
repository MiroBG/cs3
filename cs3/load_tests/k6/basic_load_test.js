import http from 'k6/http';
import { sleep, check } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '60s', target: 50 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    'http_req_failed{status:200}': ['rate<0.01'],
  },
};

const BASE = __ENV.K6_HOST || 'http://localhost:8080';

export default function () {
  const res = http.get(`${BASE}/`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
