"""Wait for cluster formation from the client network, not just TCP listen."""
import argparse
import socket
import time


def ready(payload, nodes):
    fields = dict(line.split('\t', 1) for line in payload.splitlines() if '\t' in line)
    stats = dict(item.split('=', 1) for item in fields.get('statistics', '').split(';') if '=' in item)
    try:
        return int(fields.get('partition-generation', '-1')) >= 0 and int(stats.get('cluster_size', '0')) == nodes
    except ValueError:
        return False


def recv_exact(sock, count):
    result = bytearray()
    while len(result) < count:
        part = sock.recv(count - len(result))
        if not part:
            raise ConnectionError('incomplete info response')
        result.extend(part)
    return bytes(result)


def probe(host):
    request = b'partition-generation\nstatistics\n'
    with socket.create_connection((host, 3000), timeout=2) as sock:
        sock.sendall(bytes([2, 1]) + len(request).to_bytes(6, 'big') + request)
        header = recv_exact(sock, 8)
        size = int.from_bytes(header[2:], 'big')
        if header[:2] != bytes([2, 1]) or size > 1024 * 1024:
            raise ValueError('invalid info response')
        return recv_exact(sock, size).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('hosts', nargs='+')
    parser.add_argument('--nodes', type=int, default=1)
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            if all(ready(probe(host), args.nodes) for host in args.hosts):
                print(f'CLUSTER_READY nodes={args.nodes} hosts={args.hosts}')
                return
        except (OSError, ValueError):
            pass
        time.sleep(1)
    raise SystemExit(f'cluster did not become ready within {args.timeout}s')


if __name__ == '__main__':
    main()
