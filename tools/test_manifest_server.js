#!/usr/bin/env node
// Throwaway manifest server for tests/update_service_test.gd.
// Serves one JSON body from argv[2] at argv[3] (path), then exits after
// argv[4] requests (default 12) so a crashed test cannot leak the process.
const http = require("http");
const fs = require("fs");
const body = process.argv[2];
const wantPath = process.argv[3] || "/update.json";
const maxRequests = Number(process.argv[4] || 12);

let served = 0;
const server = http.createServer((req, res) => {
	served += 1;
	if (req.url.split("?")[0] !== wantPath) {
		res.writeHead(404, { "Content-Type": "text/plain" });
		res.end("no");
	} else {
		res.writeHead(200, { "Content-Type": "application/json" });
		res.end(body);
	}
	if (served >= maxRequests) server.close(() => process.exit(0));
});

const port = Number(process.argv[5] || 38117);
const readyFile = process.argv[6];
server.listen(port, "127.0.0.1", () => {
	if (readyFile) require("fs").writeFileSync(readyFile, "READY " + port + "\n");
});
// Safety net: never outlive the test run.
setTimeout(() => process.exit(0), 60000).unref();
