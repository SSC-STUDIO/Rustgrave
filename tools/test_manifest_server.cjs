#!/usr/bin/env node
// Throwaway manifest server for tests/update_service_test.gd.
// Usage: node test_manifest_server.cjs <bodyBase64> <path> <maxRequests> <port> <readyFileBase64>
// Serves one JSON body at <path>, then exits after <maxRequests> requests (default 12)
// so a crashed test cannot leak the process.
// The body and the ready-file path are base64: on Windows, the command line Godot builds
// lets node split a JSON body at its spaces and quotes (observed), while base64 is safe.
// The .cjs extension keeps this CommonJS even when a package.json with "type": "module"
// sits above the repo (this machine has one in the home folder).
const http = require("http");
const fs = require("fs");
const decode = (value) => Buffer.from(value, "base64").toString("utf8");
const body = decode(process.argv[2]);
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
const readyFile = process.argv[6] ? decode(process.argv[6]) : "";
server.listen(port, "127.0.0.1", () => {
	if (readyFile) fs.writeFileSync(readyFile, "READY " + port + "\n");
});
// Safety net: never outlive the test run.
setTimeout(() => process.exit(0), 60000).unref();
