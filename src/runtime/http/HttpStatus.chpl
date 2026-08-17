module HttpStatus {
  proc reason(code: int): string {
    select code {
      when 200 do return "OK";
      when 201 do return "Created";
      when 202 do return "Accepted";
      when 204 do return "No Content";
      when 301 do return "Moved Permanently";
      when 302 do return "Found";
      when 303 do return "See Other";
      when 304 do return "Not Modified";
      when 307 do return "Temporary Redirect";
      when 308 do return "Permanent Redirect";
      when 400 do return "Bad Request";
      when 401 do return "Unauthorized";
      when 403 do return "Forbidden";
      when 404 do return "Not Found";
      when 405 do return "Method Not Allowed";
      when 406 do return "Not Acceptable";
      when 408 do return "Request Timeout";
      when 409 do return "Conflict";
      when 411 do return "Length Required";
      when 413 do return "Content Too Large";
      when 414 do return "URI Too Long";
      when 415 do return "Unsupported Media Type";
      when 422 do return "Unprocessable Content";
      when 429 do return "Too Many Requests";
      when 431 do return "Request Header Fields Too Large";
      when 500 do return "Internal Server Error";
      when 501 do return "Not Implemented";
      when 503 do return "Service Unavailable";
      when 505 do return "HTTP Version Not Supported";
      otherwise do return if code < 400 then "OK" else "Error";
    }
  }

  proc hasBody(code: int): bool {
    return !(code == 204 || code == 304 || (code >= 100 && code < 200));
  }
}
