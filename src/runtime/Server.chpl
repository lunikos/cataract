module Server {
  public use HttpMessage;
  public use RouteTable;
  public use Pipeline;

  private use CSocket only errnoMessage;
  private use Sockets;
  private use Connections;
  private use HttpParser;
  private use HttpWriter;
  private use HttpMethod;
  private use HttpStatus;
  private use ByteBuffer;
  private use TaskPool;
  private use Logging;
  private use HttpClock;
  private use Ssr;
  private use JsonWrite;
  private use Distribution;
  private use Group;
  private use Handshake;
  private use WebSockets;
  private use Rooms;
  private use Map;
  private use Time only sleep;

  record ServerConfig {
    var host: string = "127.0.0.1";
    var port: int = 3000;
    var backlog: int = 1024;
    var maxConcurrency: int = 512;
    var readBufferBytes: int = 16384;
    var headerTimeoutMillis: int = 10000;
    var keepAliveTimeoutMillis: int = 5000;
    var maxRequestsPerConnection: int = 256;
    var acceptPollSeconds: real = 0.0005;
    var acceptWaitMillis: int = 250;
    var drainSeconds: real = 10.0;
    var devMode: bool = false;
    var socketMaxMessageBytes: int = 1048576;
    var socketIdleTimeoutMillis: int = 300000;
    var socketSendTimeoutMillis: int = 10000;
    var socketSubprotocols: string = "";
    var affinity: Affinity = Affinity.pinned;
    var stickyKey: string = "sid";
    var listeners: ListenerMode = ListenerMode.single;
    var exposeLocaleHeader: bool = false;
    var limits: Limits;
  }
  
  class App {
    var settings: ServerConfig;
    var router: owned Router = new Router();
    var chain: Chain;
    var placement: owned Placement;
    var requestsHandled: atomic int;
    var connectionsAccepted: atomic int;

    proc init(settings: ServerConfig) {
      this.settings = settings;
      this.placement = new Placement(settings.affinity, settings.stickyKey);
    }

    proc addMiddleware(in m: shared Middleware) {
      chain.add(m);
    }

    proc group(title: string, prefix: string = "/"): shared MiddlewareGroup {
      var made = new shared MiddlewareGroup(title, prefix);
      addMiddleware(made);
      return made;
    }

    proc route(pattern: string, methodMask: int, kind: RouteKind, source: string,
               in handler: shared Handler) throws {
      router.register(pattern, methodMask, kind, source, handler);
    }

    proc listenAndServe() throws {
      router.seal();
      installShutdownHandlers();

      if settings.listeners == ListenerMode.perLocale && numLocales > 1 {
        coforall loc in Locales do on loc do
          try! serveOn(settings.port + loc.id);
        return;
      }
      serveOn(settings.port);
    }

    proc serveOn(port: int) throws {
      var listener = bindAndListen(settings.host, port, settings.backlog);
      defer listener.close();

      var gate = new Gate(limit = settings.maxConcurrency);
      gate.start();

      Logging.info("cataract listening on http://" + settings.host + ":" +
                   port:string +
                   (if settings.devMode then "  (dev)" else "") +
                   "  routes=" + router.size():string +
                   "  concurrency=" + settings.maxConcurrency:string +
                   "  locale=" + here.id:string + "/" + numLocales:string +
                   "  affinity=" + affinityName(settings.affinity));

      /* `sync` so no connection task outlives the scope holding the gate. */
      sync {
        while !shutdownRequested() {
          var idle = false;
          var sock = accept(listener, idle);
          if sock == nil {
            if idle {
              if gate.inFlight() == 0 then
                waitForConnection(listener, settings.acceptWaitMillis);
              else
                sleep(settings.acceptPollSeconds);
              continue;
            }
            if shutdownRequested() then break;
            Logging.warn("accept failed: " + errnoMessage());
            continue;
          }

          connectionsAccepted.add(1);
          gate.acquire();

          var conn = new owned Connection(sock, settings.readBufferBytes);
          conn.setTimeouts(settings.headerTimeoutMillis, settings.headerTimeoutMillis);
          conn.setNoDelay(true);

          begin with (in conn, ref gate) {
            serveConnection(conn);
            gate.release();
          }
        }

        Logging.info("shutdown requested; draining " + gate.inFlight():string +
                     " connection(s)");
        if !gate.drain(settings.drainSeconds) then
          Logging.warn("drain deadline passed with " + gate.inFlight():string +
                       " still in flight; waiting for them to finish");
      }

      Logging.info("stopped after " + requestsHandled.read():string + " request(s), " +
                   connectionsAccepted.read():string + " connection(s)");
    }

    proc serveConnection(in conn: owned Connection) {
      var served = 0;

      while true {
        if served > 0 then
          conn.setTimeouts(settings.keepAliveTimeoutMillis, settings.headerTimeoutMillis);

        var parsed = readRequest(conn, settings.limits);

        if parsed.outcome == Outcome.malformed {
          writeBareError(conn, parsed.status, parsed.detail);
          break;
        }
        if parsed.outcome != Outcome.ok then break;

        var ctx = new Context(request = parsed.request);
        ctx.requestId = requestId(conn, served);
        ctx.startedAtMillis = monoMillis();

        served += 1;
        requestsHandled.add(1);

        var keepAlive = ctx.request.keepAlive &&
                        served < settings.maxRequestsPerConnection &&
                        !shutdownRequested();

        if isUpgradeRequest(ctx.request) && serveSocket(ctx, conn.borrow()) then break;

        var res = handle(ctx);
        if res.closeConnection then keepAlive = false;

        const method = ctx.request.method;
        if !writeResponse(conn, res, method, keepAlive) then break;
        if !keepAlive then break;
      }

      conn.close();
    }

    proc serveSocket(ref ctx: Context, conn: borrowed Connection): bool {
      const m = router.match(ctx.request.path, ctx.request.method);
      if !m.found || router.kindOf(m.routeIndex) != RouteKind.socket then return false;
      ctx.params = m.params;

      var res = new Response();
      const (handled, entered) = chain.runBefore(ctx, res);
      if handled {
        chain.runAfter(ctx, res, entered);
        writeResponse(conn, res, ctx.request.method, false);
        return true;
      }

      const shake = negotiate(ctx.request, settings.socketSubprotocols);
      if !shake.accepted {
        var refused = errorResponse(shake.status, shake.detail);
        refused.setHeader("Sec-WebSocket-Version", SUPPORTED_VERSION);
        chain.runAfter(ctx, refused, entered);
        writeResponse(conn, refused, ctx.request.method, false);
        return true;
      }

      res.status = 101;
      chain.runAfter(ctx, res, entered);
      conn.write(shake.responseHead);
      if !conn.flush() then return true;

      var socket = new shared WebSocket(conn, ctx.request.path,
                                        settings.socketMaxMessageBytes,
                                        settings.socketSendTimeoutMillis,
                                        settings.socketIdleTimeoutMillis);
      Logging.info("websocket open " + ctx.request.path + " " + socket.id);
      router.dispatchSocket(m.routeIndex, ctx, socket);
      socket.markClosed();
      Rooms.leaveAll(socket);
      Logging.info("websocket close " + socket.id);
      return true;
    }

    /* Every exit unwinds through `runAfter`, so nothing strands the hardening. */
    proc handle(ref ctx: Context): Response {
      var res = new Response();
      const (handled, entered) = chain.runBefore(ctx, res);

      if !handled {
        const m = router.match(ctx.request.path, ctx.request.method);
        if m.found {
          ctx.params = m.params;
          const target = placement.localeFor(ctx);
          ctx.localeId = target;
          if target == here.id {
            res = router.dispatch(m.routeIndex, ctx);
          } else {
            on Locales[target] do res = router.dispatch(m.routeIndex, ctx);
          }
          if settings.exposeLocaleHeader then
            res.setHeader("X-Cataract-Locale", target:string);
        } else if m.methodMismatch {
          res = notAllowed(ctx, m.allow);
        } else {
          res = notFound(ctx);
        }
      }

      chain.runAfter(ctx, res, entered);
      return res;
    }

    proc notFound(const ref ctx: Context): Response {
      if wantsJson(ctx) {
        var j = new JsonBuilder();
        j.beginObject();
        j.field("error", "not_found");
        j.field("path", ctx.request.path);
        j.endObject();
        return jsonResponse(j.done(), 404);
      }
      return htmlResponse(errorPage(404, reason(404),
                                    "No route matches " + ctx.request.path), 404);
    }

    proc notAllowed(const ref ctx: Context, allow: string): Response {
      var res = if wantsJson(ctx)
                then jsonResponse("{\"error\":\"method_not_allowed\"}", 405)
                else htmlResponse(errorPage(405, reason(405),
                                            "Allowed: " + allow), 405);
      res.setHeader("Allow", allow);
      return res;
    }

    proc wantsJson(const ref ctx: Context): bool {
      /* No pages means no HTML surface, so errors must not arrive as documents. */
      if router.pageCount() == 0 then return true;
      if ctx.request.path.startsWith("/api/") then return true;
      const accept = ctx.request.header("Accept");
      return accept.find("application/json") != -1 && accept.find("text/html") == -1;
    }

    proc requestId(conn: borrowed Connection, seq: int): string {
      return conn.peerIp() + ":" + conn.peerPort():string + "#" + seq:string;
    }
  }
}
