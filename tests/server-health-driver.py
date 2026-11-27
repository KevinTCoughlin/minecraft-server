#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the server-health probe against local TCP and UDP peers.

The probe is the Python block extracted from .github/workflows/server-health.yml.
Nothing here contacts a public server. Bedrock is up on any HTTP status from
NetherNet signaling, and a RakNet pong still counts when signaling does not answer.
"""

import json
import os
import socket
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def encode_varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            byte |= 0x80
        out.append(byte)
        if value == 0:
            return bytes(out)


def encode_packet(packet_id, data):
    payload = encode_varint(packet_id) + data
    return encode_varint(len(payload)) + payload


def take_varint(buf, index):
    value = 0
    for shift in range(0, 35, 7):
        if index >= len(buf):
            return None
        byte = buf[index]
        index += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, index
    return None


def take_packet(buf, index):
    parsed = take_varint(buf, index)
    if parsed is None:
        return None
    length, index = parsed
    if length < 1 or index + length > len(buf):
        return None
    return buf[index:index + length], index + length


def parse_handshake(buf):
    """Return True when buf is a status handshake plus an empty status request."""
    first = take_packet(buf, 0)
    if first is None:
        return None
    packet, index = first
    parsed = take_varint(packet, 0)
    if parsed is None or parsed[0] != 0:
        return False
    cursor = parsed[1]
    parsed = take_varint(packet, cursor)
    if parsed is None:
        return False
    _protocol, cursor = parsed
    parsed = take_varint(packet, cursor)
    if parsed is None:
        return False
    host_len, cursor = parsed
    if cursor + host_len + 2 > len(packet):
        return False
    cursor += host_len + 2
    parsed = take_varint(packet, cursor)
    if parsed is None or parsed[0] != 1 or parsed[1] != len(packet):
        return False
    second = take_packet(buf, index)
    if second is None:
        return None
    request, end = second
    if end != len(buf):
        return False
    parsed = take_varint(request, 0)
    if parsed is None or parsed != (0, len(request)):
        return False
    return True


def status_packet(payload):
    body = json.dumps(payload).encode("utf-8")
    return encode_packet(0, encode_varint(len(body)) + body)


def java_status(name="Paper 26.3", online=1, maximum=20, description="dev"):
    return {
        "version": {"name": name, "protocol": 769},
        "players": {"online": online, "max": maximum},
        "description": {"text": description},
    }


def raknet_pong(identity):
    encoded = identity.encode("utf-8")
    return (
        b"\x1c"
        + (0).to_bytes(8, "big")
        + (1).to_bytes(8, "big")
        + MAGIC
        + struct.pack(">H", len(encoded))
        + encoded
    )


def java_peer(mode, payload, ready, errors, stats):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", 0))
        sock.listen(8)
        stats["port"] = sock.getsockname()[1]
        ready.set()
        sock.settimeout(0.2)
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                conn, _addr = sock.accept()
            except socket.timeout:
                if stats.get("done"):
                    return
                continue
            stats["accepts"] = stats.get("accepts", 0) + 1
            try:
                serve_java(conn, mode, payload, errors, stats)
            except Exception as exc:  # noqa: BLE001 - surface peer bugs to the test
                errors.append(f"java peer: {exc!r}")
            if stats.get("done"):
                return
    except Exception as exc:  # noqa: BLE001
        errors.append(f"java peer: {exc!r}")
        ready.set()
    finally:
        sock.close()


def serve_java(conn, mode, payload, errors, stats):
    with conn:
        conn.settimeout(0.5)
        if mode == "junk":
            conn.sendall(b"OK\n")
            return
        if mode == "flaky" and stats["accepts"] == 1:
            return
        buf = b""
        deadline = time.time() + 1
        while time.time() < deadline:
            parsed = parse_handshake(buf)
            if parsed is True:
                stats["handshake"] = stats.get("handshake", 0) + 1
                conn.sendall(status_packet(payload))
                stats["done"] = True
                return
            if parsed is False:
                errors.append(f"not a status handshake: {buf!r}")
                return
            try:
                chunk = conn.recv(1024)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
        errors.append(f"incomplete handshake: {buf!r}")


def http_response(status):
    phrases = {200: "OK", 204: "No Content", 404: "Not Found", 500: "Error"}
    phrase = phrases.get(status, "OK")
    return (
        f"HTTP/1.1 {int(status)} {phrase}\r\n"
        "content-length: 0\r\n"
        "connection: close\r\n"
        "\r\n"
    ).encode("ascii")


def serve_http(conn, status, stats):
    with conn:
        conn.settimeout(0.5)
        buf = b""
        deadline = time.time() + 1
        while time.time() < deadline and b"\r\n\r\n" not in buf and len(buf) < 2048:
            try:
                chunk = conn.recv(1024)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
        stats["request"] = buf
        if status == "junk":
            conn.sendall(b"OK\n")
        elif status != "close":
            conn.sendall(http_response(status))
        stats["done"] = True


def http_peer(status, ready, errors, stats):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", stats.get("bind_port", 0)))
        sock.listen(8)
        stats["port"] = sock.getsockname()[1]
        ready.set()
        sock.settimeout(0.2)
        deadline = time.time() + 8
        while time.time() < deadline:
            if stats.get("done"):
                return
            try:
                conn, _addr = sock.accept()
            except socket.timeout:
                continue
            stats["accepts"] = stats.get("accepts", 0) + 1
            try:
                serve_http(conn, status, stats)
            except Exception as exc:  # noqa: BLE001 - surface peer bugs to the test
                errors.append(f"http peer: {exc!r}")
            if stats.get("done"):
                return
    except Exception as exc:  # noqa: BLE001
        errors.append(f"http peer: {exc!r}")
        ready.set()
    finally:
        sock.close()


def bedrock_peer(mode, packet, ready, errors, stats):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", stats.get("bind_port", 0)))
        stats["port"] = sock.getsockname()[1]
        ready.set()
        sock.settimeout(0.2)
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                data, addr = sock.recvfrom(2048)
            except socket.timeout:
                if stats.get("done") or mode == "blackhole" and stats.get("pings", 0) >= 2:
                    return
                continue
            if len(data) == 33 and data[0] == 0x01 and data[9:25] == MAGIC:
                stats["pings"] = stats.get("pings", 0) + 1
            else:
                errors.append(f"bad unconnected ping: {data!r}")
                return
            if mode == "blackhole":
                continue
            if mode == "bad-magic" and stats["pings"] == 1:
                sock.sendto(b"\x1c" + b"\x00" * 40, addr)
                stats["done"] = True
                return
            if mode == "flaky" and stats["pings"] == 1:
                continue
            sock.sendto(packet, addr)
            stats["done"] = True
            return
    except Exception as exc:  # noqa: BLE001
        errors.append(f"bedrock peer: {exc!r}")
        ready.set()
    finally:
        sock.close()


def start_peer(target, args, port=None):
    ready = threading.Event()
    errors = []
    stats = {}
    if port is not None:
        stats["bind_port"] = port
    thread = threading.Thread(target=target, args=(*args, ready, errors, stats), daemon=True)
    thread.start()
    if not ready.wait(2):
        fail("peer did not bind")
    if "port" not in stats:
        fail(f"peer failed before bind: {errors}")
    return thread, errors, stats


def parse_output(text):
    values = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if "<<" in line:
            name, end = line.split("<<", 1)
            body = []
            index += 1
            while index < len(lines) and lines[index] != end:
                body.append(lines[index])
                index += 1
            values[name] = "\n".join(body)
        elif "=" in line:
            name, value = line.split("=", 1)
            values[name] = value
        index += 1
    return values


def run_probe(probe, output, **kwargs):
    env = {
        "PATH": os.environ.get("PATH", ""),
        "GITHUB_OUTPUT": str(output),
        "MC_HEALTH_TRIES": kwargs.get("tries", "1"),
        "MC_HEALTH_TIMEOUT": kwargs.get("timeout", "0.4"),
        "MC_HEALTH_GAP": kwargs.get("gap", "0"),
    }
    if kwargs.get("host", "127.0.0.1") is not None:
        env["MC_HEALTH_HOST"] = kwargs.get("host", "127.0.0.1")
    if "java" in kwargs and kwargs["java"] is not None:
        env["MC_HEALTH_JAVA_PORT"] = str(kwargs["java"])
    if "bedrock" in kwargs and kwargs["bedrock"] is not None:
        env["MC_HEALTH_BEDROCK_PORT"] = str(kwargs["bedrock"])
    for key, value in kwargs.get("extra", {}).items():
        env[key] = value
    if output.exists():
        output.unlink()
    return subprocess.run(
        [sys.executable, str(probe)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def read_outputs(path):
    if not path.exists():
        return {}
    return parse_output(path.read_text(encoding="utf-8"))


def expect_ok(name, proc):
    if proc.returncode != 0:
        fail(f"{name}: exit {proc.returncode}\n{proc.stderr}\n{proc.stdout}")


def join(thread, errors, name):
    thread.join(2)
    if errors:
        fail(f"{name}: {errors}")


def finish(thread, errors, stats, name):
    stats["done"] = True
    join(thread, errors, name)


def main():
    if len(sys.argv) != 3:
        fail("usage: server-health-driver.py PROBE OUTPUT_DIR")
    probe = Path(sys.argv[1])
    work = Path(sys.argv[2])
    identity = "MCPE;Dev;800;1.21.50;2;20;123;Bedrock level;Survival;1;19132;19133;"

    java_thread, java_errors, java_stats = start_peer(
        java_peer, ("status", java_status())
    )
    bedrock_thread, bedrock_errors, bedrock_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity))
    )
    out = work / "both.txt"
    proc = run_probe(
        probe, out, java=java_stats["port"], bedrock=bedrock_stats["port"]
    )
    join(java_thread, java_errors, "java")
    join(bedrock_thread, bedrock_errors, "bedrock")
    expect_ok("both up", proc)
    if java_stats.get("handshake") != 1:
        fail(f"probe did not send a status handshake: {java_stats}")
    if bedrock_stats.get("pings") != 1:
        fail(f"probe did not send an unconnected ping: {bedrock_stats}")
    if f"127.0.0.1:{java_stats['port']} up: Paper 26.3, players 1/20" not in proc.stdout:
        fail(f"java name missing\n{proc.stdout}")
    if f"127.0.0.1:{bedrock_stats['port']} up: Dev, 1.21.50, players 2/20" not in proc.stdout:
        fail(f"bedrock name missing\n{proc.stdout}")
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"both up should leave down empty, got {values.get('down')!r}")
    if values.get("skipped") != "false":
        fail(f"both up skipped={values.get('skipped')!r}")
    detail = values.get("detail", "")
    if f"- {java_stats['port']} up: Paper 26.3, players 1/20" not in detail:
        fail(f"java detail missing\n{detail}")
    if f"- {bedrock_stats['port']} up: Dev, 1.21.50, players 2/20" not in detail:
        fail(f"bedrock detail missing\n{detail}")
    print("ok: status handshake and RakNet pong")

    # An accepted TCP connection that is not a status response is down.
    junk_thread, junk_errors, junk_stats = start_peer(java_peer, ("junk", {}))
    good_thread, good_errors, good_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity))
    )
    out = work / "junk.txt"
    proc = run_probe(probe, out, java=junk_stats["port"], bedrock=good_stats["port"])
    join(good_thread, good_errors, "junk-bedrock")
    junk_thread.join(2)
    if junk_errors:
        fail(f"junk peer: {junk_errors}")
    expect_ok("junk tcp", proc)
    values = read_outputs(out)
    if values.get("down") != str(junk_stats["port"]):
        fail(f"open non-minecraft port should be down, got {values.get('down')!r}\n{proc.stdout}")
    print("ok: an open TCP port without a status handshake is down")

    # A UDP reply that is not a RakNet pong is down.
    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    bad_thread, bad_errors, bad_stats = start_peer(bedrock_peer, ("bad-magic", b""))
    out = work / "badmagic.txt"
    proc = run_probe(probe, out, java=java_stats["port"], bedrock=bad_stats["port"])
    join(java_thread, java_errors, "badmagic-java")
    join(bad_thread, bad_errors, "badmagic")
    expect_ok("bad magic", proc)
    values = read_outputs(out)
    if values.get("down") != str(bad_stats["port"]):
        fail(f"bad magic should be down, got {values.get('down')!r}\n{proc.stdout}")
    print("ok: UDP without RakNet magic is down")

    # Framed JSON that is not a server-list status is down.
    java_thread, java_errors, java_stats = start_peer(
        java_peer, ("status", {"ok": True})
    )
    bedrock_thread, bedrock_errors, bedrock_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity))
    )
    out = work / "notstatus.txt"
    proc = run_probe(
        probe, out, java=java_stats["port"], bedrock=bedrock_stats["port"]
    )
    join(java_thread, java_errors, "notstatus-java")
    join(bedrock_thread, bedrock_errors, "notstatus-bedrock")
    expect_ok("not status", proc)
    values = read_outputs(out)
    if values.get("down") != str(java_stats["port"]):
        fail(f"non-status JSON should be down, got {values.get('down')!r}\n{proc.stdout}")
    print("ok: JSON without version or players is down")

    # Favicon-sized status payloads still count. A short read cap would miss them.
    large = java_status(description="x" * 40000)
    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", large))
    bedrock_thread, bedrock_errors, bedrock_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity))
    )
    out = work / "large.txt"
    proc = run_probe(
        probe, out, java=java_stats["port"], bedrock=bedrock_stats["port"], timeout="1"
    )
    join(java_thread, java_errors, "large-java")
    join(bedrock_thread, bedrock_errors, "large-bedrock")
    expect_ok("large status", proc)
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"large status should be up, got {values.get('down')!r}\n{proc.stderr}")
    print("ok: a status payload with a large description is up")

    # First try fails, the retry gets a real reply. One miss is not "down".
    java_thread, java_errors, java_stats = start_peer(java_peer, ("flaky", java_status()))
    bedrock_thread, bedrock_errors, bedrock_stats = start_peer(
        bedrock_peer, ("flaky", raknet_pong(identity))
    )
    out = work / "retry.txt"
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=bedrock_stats["port"],
        tries="2",
        gap="0",
    )
    join(java_thread, java_errors, "retry-java")
    join(bedrock_thread, bedrock_errors, "retry-bedrock")
    expect_ok("retry", proc)
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"retry should recover, got {values.get('down')!r}\n{proc.stdout}")
    if java_stats.get("accepts") != 2 or bedrock_stats.get("pings") != 2:
        fail(f"retry did not ask twice: java {java_stats} bedrock {bedrock_stats}")
    print("ok: a dropped query is retried and then up")

    # NetherNet signaling: any HTTP status on TCP is up, and RakNet is not asked.
    # 404 is what Geyser's built-in server answers for GET /.
    for status in (404, 200, 500):
        java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
        http_thread, http_errors, http_stats = start_peer(http_peer, (status,))
        udp_thread, udp_errors, udp_stats = start_peer(
            bedrock_peer, ("blackhole", b""), port=http_stats["port"]
        )
        out = work / f"http{status}.txt"
        proc = run_probe(
            probe,
            out,
            java=java_stats["port"],
            bedrock=http_stats["port"],
            extra={"MC_HEALTH_BEDROCK_MODE": "nethernet"},
        )
        finish(java_thread, java_errors, java_stats, f"http{status}-java")
        finish(http_thread, http_errors, http_stats, f"http{status}")
        finish(udp_thread, udp_errors, udp_stats, f"http{status}-udp")
        expect_ok(f"http {status}", proc)
        values = read_outputs(out)
        if values.get("down") != "":
            fail(f"HTTP {status} should be up, got {values.get('down')!r}\n{proc.stdout}")
        if f"up: NetherNet, HTTP {status}" not in proc.stdout:
            fail(f"HTTP {status} detail missing\n{proc.stdout}")
        if udp_stats.get("pings", 0) != 0:
            fail(f"HTTP {status} should not send RakNet, pings={udp_stats.get('pings')}")
        if status == 404:
            request = http_stats.get("request", b"")
            if not request.startswith(b"GET / HTTP/1.1\r\n"):
                fail(f"signaling probe was not an HTTP GET, got {request!r}")
    print("ok: any NetherNet HTTP status is up, including 404")

    # An accepted TCP connection that does not speak HTTP is not signaling.
    # With no RakNet pong, the port stays down.
    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    junk_http, junk_http_errors, junk_http_stats = start_peer(http_peer, ("junk",))
    junk_udp, junk_udp_errors, junk_udp_stats = start_peer(
        bedrock_peer, ("blackhole", b""), port=junk_http_stats["port"]
    )
    out = work / "httpjunk.txt"
    proc = run_probe(probe, out, java=java_stats["port"], bedrock=junk_http_stats["port"])
    finish(java_thread, java_errors, java_stats, "httpjunk-java")
    finish(junk_http, junk_http_errors, junk_http_stats, "httpjunk")
    finish(junk_udp, junk_udp_errors, junk_udp_stats, "httpjunk-udp")
    expect_ok("http junk", proc)
    values = read_outputs(out)
    if values.get("down") != str(junk_http_stats["port"]):
        fail(f"non-HTTP TCP should be down, got {values.get('down')!r}\n{proc.stdout}")
    if junk_udp_stats.get("pings", 0) < 1:
        fail(f"non-HTTP TCP should fall back to RakNet, stats {junk_udp_stats}")
    detail = values.get("detail", "")
    if "no NetherNet HTTP response or RakNet unconnected pong" not in detail:
        fail(f"non-HTTP detail missing the fallback reason\n{detail}")
    print("ok: TCP that accepts but is not HTTP is down")

    # raknet mode ignores signaling. HTTP 404 alone is down; a pong is still up.
    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    http_thread, http_errors, http_stats = start_peer(http_peer, (404,))
    udp_thread, udp_errors, udp_stats = start_peer(
        bedrock_peer, ("blackhole", b""), port=http_stats["port"]
    )
    out = work / "raknet-http.txt"
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=http_stats["port"],
        extra={"MC_HEALTH_BEDROCK_MODE": "raknet"},
    )
    finish(java_thread, java_errors, java_stats, "raknet-http-java")
    finish(http_thread, http_errors, http_stats, "raknet-http")
    finish(udp_thread, udp_errors, udp_stats, "raknet-http-udp")
    expect_ok("raknet ignores http", proc)
    values = read_outputs(out)
    if values.get("down") != str(http_stats["port"]):
        fail(f"raknet mode should ignore HTTP, got {values.get('down')!r}\n{proc.stdout}")
    if http_stats.get("accepts", 0) != 0:
        fail(f"raknet mode opened signaling: {http_stats}")
    if udp_stats.get("pings", 0) < 1:
        fail(f"raknet mode did not ping: {udp_stats}")
    print("ok: raknet mode ignores NetherNet HTTP")

    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    http_thread, http_errors, http_stats = start_peer(http_peer, (404,))
    udp_thread, udp_errors, udp_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity)), port=http_stats["port"]
    )
    out = work / "raknet-pong.txt"
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=http_stats["port"],
        extra={"MC_HEALTH_BEDROCK_MODE": "raknet"},
    )
    finish(java_thread, java_errors, java_stats, "raknet-pong-java")
    finish(http_thread, http_errors, http_stats, "raknet-pong-http")
    finish(udp_thread, udp_errors, udp_stats, "raknet-pong")
    expect_ok("raknet pong", proc)
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"raknet mode pong should be up, got {values.get('down')!r}\n{proc.stdout}")
    if "up: Dev, 1.21.50, players 2/20" not in proc.stdout:
        fail(f"raknet mode did not report the pong\n{proc.stdout}")
    if http_stats.get("accepts", 0) != 0:
        fail(f"raknet mode opened signaling beside a pong: {http_stats}")
    print("ok: raknet mode still counts a RakNet pong")

    # either: signaling alone is up, and so is a pong when nothing accepts TCP.
    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    http_thread, http_errors, http_stats = start_peer(http_peer, (404,))
    udp_thread, udp_errors, udp_stats = start_peer(
        bedrock_peer, ("blackhole", b""), port=http_stats["port"]
    )
    out = work / "either-http.txt"
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=http_stats["port"],
        extra={"MC_HEALTH_BEDROCK_MODE": "Either"},
    )
    finish(java_thread, java_errors, java_stats, "either-http-java")
    finish(http_thread, http_errors, http_stats, "either-http")
    finish(udp_thread, udp_errors, udp_stats, "either-http-udp")
    expect_ok("either http", proc)
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"either mode should accept HTTP, got {values.get('down')!r}\n{proc.stdout}")
    if udp_stats.get("pings", 0) != 0:
        fail("either mode should not ping after HTTP answered")
    print("ok: either mode counts NetherNet HTTP")

    java_thread, java_errors, java_stats = start_peer(java_peer, ("status", java_status()))
    udp_thread, udp_errors, udp_stats = start_peer(
        bedrock_peer, ("pong", raknet_pong(identity))
    )
    out = work / "either-raknet.txt"
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=udp_stats["port"],
        extra={"MC_HEALTH_BEDROCK_MODE": "either"},
    )
    finish(java_thread, java_errors, java_stats, "either-raknet-java")
    finish(udp_thread, udp_errors, udp_stats, "either-raknet")
    expect_ok("either raknet", proc)
    values = read_outputs(out)
    if values.get("down") != "":
        fail(f"either mode should accept a RakNet fallback, got {values.get('down')!r}\n{proc.stdout}")
    if udp_stats.get("pings") != 1:
        fail(f"either mode did not fall back to one ping: {udp_stats}")
    print("ok: either mode counts a RakNet pong when signaling is absent")

    # Both tries fail. The port stays down and each probe was sent twice.
    java_thread, java_errors, java_stats = start_peer(java_peer, ("junk", {}))
    bedrock_thread, bedrock_errors, bedrock_stats = start_peer(
        bedrock_peer, ("blackhole", b"")
    )
    out = work / "twice.txt"
    started = time.monotonic()
    proc = run_probe(
        probe,
        out,
        java=java_stats["port"],
        bedrock=bedrock_stats["port"],
        tries="2",
        timeout="0.15",
        gap="0.3",
    )
    elapsed = time.monotonic() - started
    java_thread.join(2)
    bedrock_thread.join(2)
    if java_errors or bedrock_errors:
        fail(f"twice: {java_errors} {bedrock_errors}")
    expect_ok("twice", proc)
    values = read_outputs(out)
    wanted = f"{java_stats['port']} {bedrock_stats['port']}"
    if values.get("down") != wanted:
        fail(f"both down={values.get('down')!r}, wanted {wanted}")
    if java_stats.get("accepts", 0) < 2 or bedrock_stats.get("pings", 0) < 2:
        fail(f"down before a retry: java {java_stats} bedrock {bedrock_stats}")
    # Two gaps (one per port) at 0.3s. A probe that does not sleep finishes sooner.
    if elapsed < 0.5:
        fail(f"retries did not wait between tries ({elapsed:.2f}s)")
    print("ok: still down after a retry, and the gap is honored")

    # Unset ports mean 25565 and 19132. Hold TCP 25565, and both TCP and UDP
    # 19132, so nothing else can answer Java status, NetherNet signaling, or RakNet.
    holders = []
    try:
        for port, kind in (
            (25565, socket.SOCK_STREAM),
            (19132, socket.SOCK_STREAM),
            (19132, socket.SOCK_DGRAM),
        ):
            held = socket.socket(socket.AF_INET, kind)
            held.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                held.bind(("127.0.0.1", port))
            except OSError as exc:
                fail(f"could not hold 127.0.0.1:{port} ({kind}): {exc}")
            if kind == socket.SOCK_STREAM:
                held.listen(8)
            holders.append(held)
        out = work / "default.txt"
        proc = run_probe(probe, out, timeout="0.2", tries="1")
    finally:
        for held in holders:
            held.close()
    expect_ok("default ports", proc)
    values = read_outputs(out)
    if values.get("down") != "25565 19132":
        fail(f"default down list is {values.get('down')!r}\n{proc.stdout}")
    detail = values.get("detail", "")
    if "- 25565 down:" not in detail or "- 19132 down:" not in detail:
        fail(f"default detail missing a port\n{detail}")
    if "no NetherNet HTTP response or RakNet unconnected pong" not in detail:
        fail(f"default bedrock detail should name signaling and RakNet\n{detail}")
    print("ok: unset ports check TCP 25565 and Bedrock TCP/UDP 19132")

    missing = run_probe(probe, work / "missing.txt", host=None)
    if missing.returncode != 0:
        fail(f"unset host should skip, exit {missing.returncode}: {missing.stderr}")
    if "::notice title=Server health::" not in missing.stdout or "MC_HEALTH_HOST is unset" not in missing.stdout:
        fail(f"unset host should print a notice\n{missing.stdout}")
    values = read_outputs(work / "missing.txt")
    if values.get("skipped") != "true" or values.get("down") != "":
        fail(f"unset host outputs {values}")
    print("ok: unset MC_HEALTH_HOST skips with a notice")

    bad = run_probe(probe, work / "bad.txt", java="nope", bedrock="19132")
    if bad.returncode == 0 or "MC_HEALTH_JAVA_PORT must be an integer" not in (bad.stderr or ""):
        fail(f"bad port should fail\n{bad.stderr}")
    zero = run_probe(probe, work / "zero.txt", extra={"MC_HEALTH_TRIES": "0"})
    if zero.returncode == 0:
        fail("tries of 0 should fail")
    bad_mode = run_probe(
        probe, work / "badmode.txt", extra={"MC_HEALTH_BEDROCK_MODE": "tcp"}
    )
    if bad_mode.returncode == 0 or "MC_HEALTH_BEDROCK_MODE must be nethernet, raknet or either" not in (
        bad_mode.stderr or ""
    ):
        fail(f"bad bedrock mode should fail\n{bad_mode.stderr}")
    print("ok: a broken configuration exits 1")

    print("server health probe tests passed")


if __name__ == "__main__":
    main()
