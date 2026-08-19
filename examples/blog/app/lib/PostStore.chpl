module PostStore {
  record Post {
    var id: string;
    var title: string;
    var summary: string;
    var body: string;
    var published: string;
  }

  private const posts = [
    new Post("hello-chapel",
             "Why Chapel for a web runtime",
             "Task parallelism and C interop in one language.",
             "Chapel gives a request handler real parallelism without a callback " +
             "colouring problem: a blocking read inside a task blocks that task, " +
             "not the scheduler.",
             "2026-01-14"),
    new Post("island-architecture",
             "Islands, not hydration",
             "Ship JavaScript only where behaviour actually lives.",
             "A page renders to final markup on the server. Interactive regions " +
             "declare themselves, and only those regions receive a client bundle.",
             "2026-02-02"),
    new Post("zero-copy-parsing",
             "Parsing HTTP without copying",
             "A sliding window over one buffer per connection.",
             "The parser works over byte offsets into the connection's read " +
             "buffer, so a request line becomes a string exactly once.",
             "2026-03-19")
  ];

  iter all() {
    for p in posts do yield p;
  }

  proc count(): int do return posts.size;

  proc find(id: string, ref result: Post): bool {
    for p in posts {
      if p.id == id {
        result = p;
        return true;
      }
    }
    return false;
  }

  proc exists(id: string): bool {
    for p in posts do
      if p.id == id then return true;
    return false;
  }
}
