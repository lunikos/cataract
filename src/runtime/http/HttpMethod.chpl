module HttpMethod {
  enum Method { get = 0, head = 1, post = 2, put = 3, patch = 4, del = 5, options = 6, unknown = 7 }

  proc parseMethod(s: string): Method {
    select s {
      when "GET"     do return Method.get;
      when "HEAD"    do return Method.head;
      when "POST"    do return Method.post;
      when "PUT"     do return Method.put;
      when "PATCH"   do return Method.patch;
      when "DELETE"  do return Method.del;
      when "OPTIONS" do return Method.options;
      otherwise      do return Method.unknown;
    }
  }

  proc methodName(m: Method): string {
    select m {
      when Method.get     do return "GET";
      when Method.head    do return "HEAD";
      when Method.post    do return "POST";
      when Method.put     do return "PUT";
      when Method.patch   do return "PATCH";
      when Method.del  do return "DELETE";
      when Method.options do return "OPTIONS";
      otherwise           do return "UNKNOWN";
    }
  }

  /* HEAD is served by the GET handler with the body elided at write time. */
  proc effectiveMethod(m: Method): Method {
    return if m == Method.head then Method.get else m;
  }
}
