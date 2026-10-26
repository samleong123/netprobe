// Fixtures for the app's upload contracts: raw POST payloads, HTTP success
// for custom servers, and a positive size acknowledgement for Speedtest.
const http = require('http');

http.createServer((req, res) => {
  if (req.method !== 'POST' || req.headers['content-type'] !== 'application/octet-stream') {
    res.writeHead(501);
    return res.end();
  }
  const path = req.url.split('?')[0];
  const size = Number(req.headers['content-length']);
  if (!Number.isInteger(size) || size < 0) {
    res.writeHead(400);
    return res.end();
  }
  req.resume();
  switch (path) {
    case '/empty':
      res.writeHead(200);
      return res.end();
    case '/json':
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true }));
    case '/invalid-size':
      res.writeHead(200);
      return res.end('size=0');
    case '/size':
      res.writeHead(200);
      return res.end(`size=${size}`);
    case '/redirect':
      res.writeHead(307, { Location: 'empty' });
      return res.end();
    case '/rejected':
      res.writeHead(403);
      return res.end();
    default:
      res.writeHead(501);
      return res.end();
  }
}).listen(process.env.PORT || 4500);
