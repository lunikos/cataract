module Connections {
  private use CSocket;
  private use Sockets;
  private use ByteBuffer;
  private use Logging;
  private use HttpClock only monoMillis;
  private use Time only sleep;
  private config const minPollSeconds = 0.0002;
  private config const maxPollSeconds = 0.004;

  enum ReadState { ok, eof, timeout, failed }

  class Connection {
    var sock: owned Socket?;
    var inDom: domain(1);
    var inBuf: [inDom] uint(8);
    var start: int = 0;
    var stop: int = 0;
    var readTimeoutMillis: int = 10000;
    var writeTimeoutMillis: int = 10000;

    var readDeadlineMillis: int = -1;
    var outBuf: Bytes;
    var lastState: ReadState = ReadState.ok;
    var bytesIn: int = 0;
    var bytesOut: int = 0;

    proc init(in sock: owned Socket?, bufferSize: int = 16384) {
      this.sock = sock;
      this.inDom = {0..<bufferSize};
    }

    proc buffered(): int do return stop - start;

    proc compact() {
      if start == 0 then return;
      const n = stop - start;
      if n > 0 then
        for i in 0..<n do inBuf[i] = inBuf[start + i];
      start = 0;
      stop = n;
    }

    proc growTo(minCapacity: int, hardLimit: int): bool {
      if inDom.size >= minCapacity then return true;
      if minCapacity > hardLimit then return false;
      var cap = inDom.size;
      while cap < minCapacity do cap *= 2;
      if cap > hardLimit then cap = hardLimit;
      inDom = {0..<cap};
      return true;
    }

    proc fill(): ReadState {
      compact();
      if stop >= inDom.size then return ReadState.failed;

      var deadline = monoMillis() + readTimeoutMillis;
      if readDeadlineMillis >= 0 then deadline = min(deadline, readDeadlineMillis);
      var wait = minPollSeconds;

      while true {
        const n = cat_recv(sock!.fd, c_ptrTo(inBuf[stop]): c_ptr(void),
                           (inDom.size - stop): c_size_t);
        if n > 0 {
          stop += n: int;
          bytesIn += n: int;
          lastState = ReadState.ok;
          return lastState;
        }
        if n == 0 {
          lastState = ReadState.eof;
          return lastState;
        }
        if n != WOULD_BLOCK {
          lastState = ReadState.failed;
          return lastState;
        }
        if monoMillis() >= deadline {
          lastState = ReadState.timeout;
          return lastState;
        }
        sleep(wait);
        wait = min(wait * 2, maxPollSeconds);
      }
      return lastState;
    }

    proc consume(n: int) {
      start += n;
      if start > stop then start = stop;
      if start == stop {
        start = 0;
        stop = 0;
      }
    }

    proc write(s: string) do outBuf.append(s);
    proc writeBytes(const ref b: Bytes) do outBuf.append(b);

    proc flush(): bool {
      if outBuf.len == 0 then return true;

      const total = outBuf.len;
      const deadline = monoMillis() + writeTimeoutMillis;
      var wait = minPollSeconds;
      var sent = 0;
      var ok = true;

      while sent < total {
        const n = cat_send(sock!.fd, (outBuf.ptrConst() + sent): c_ptrConst(void),
                           (total - sent): c_size_t);
        if n > 0 {
          sent += n: int;
          wait = minPollSeconds;
          continue;
        }
        if n != WOULD_BLOCK {
          Logging.debug("send failed on " + sock!.peerIp + ": " + errnoMessage());
          ok = false;
          break;
        }
        if monoMillis() >= deadline {
          Logging.debug("send timed out on " + sock!.peerIp);
          ok = false;
          break;
        }
        sleep(wait);
        wait = min(wait * 2, maxPollSeconds);
      }

      bytesOut += sent;
      outBuf.clear();
      return ok;
    }

    proc close() {
      sock!.close();
    }

    proc setTimeouts(recvMillis: int, sendMillis: int) {
      readTimeoutMillis = recvMillis;
      writeTimeoutMillis = sendMillis;
    }

    proc startReadDeadline(budgetMillis: int) {
      readDeadlineMillis = if budgetMillis > 0 then monoMillis() + budgetMillis else -1;
    }

    proc clearReadDeadline() do readDeadlineMillis = -1;

    proc setNoDelay(enable: bool) {
      sock!.setNoDelay(enable);
    }

    proc descriptor(): c_int do return sock!.fd;

    proc peerIp(): string do return sock!.peerIp;
    proc peerPort(): int do return sock!.peerPort;
  }
}
